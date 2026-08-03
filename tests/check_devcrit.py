#!/usr/bin/env python3
"""Build gate: the Devastating Critical rework (roadmap devcrit-roll) is wired.

unpacked/devcrit_atk.nss runs on EVERY attack on the server and
unpacked/devcrit_eff.nss on every effect applied. A mistake in either is a
mistake in all combat, and every failure mode is silent: the plugin simply is
not loaded, or the handler is not registered, or the guard that makes the hot
path cheap has been edited away, and combat carries on looking normal while the
feature does nothing. This checks the things that cannot be seen from the game.

  1. Both halves of enabling the plugin moved together: the include is in
     unpacked/ AND server.env sets NWNX_DAMAGE_SKIP=n. Copying the include
     without the env flip gives per-call "Plugin not loaded" errors and nothing
     else.
  2. onmoduleload.nss registers both handlers, and both scripts exist.
  3. devcrit_atk.nss still returns early on anything that is not a critical,
     before it does any other work.
  4. devcrit_eff.nss discriminates on the internal effect type AND on the
     attack handler's flag. Skipping death effects on the type alone would
     suppress Finger of Death, Death Attack and every scripted death in the
     module.
  5. The published numbers in roadmap.yaml's devcrit-roll card still match the
     constants in devcrit_inc.nss, so the code and the player-facing design
     cannot drift apart.
  6. The save-or-die is still disabled AT SOURCE: hak_2da/baseitems.2da's
     EpicWeaponDevastatingCriticalFeat column is blank on every row, and the
     mapping it used to hold still exists in the generated
     unpacked/devcrit_map_inc.nss. Either half alone is a silent failure — a
     re-extracted baseitems.2da brings the instant kill back, and an empty
     include takes the replacement dice away from every weapon.
"""
import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
UNPACKED = ROOT / "unpacked"

errors = []


def read(path):
    try:
        return path.read_text(encoding="latin-1")
    except OSError as exc:
        errors.append(f"cannot read {path}: {exc}")
        return ""


# --- 1. plugin enabled on both sides ---------------------------------------
if not (UNPACKED / "nwnx_damage.nss").is_file():
    errors.append(
        "unpacked/nwnx_damage.nss is missing — copy it from .nwnx_includes/. "
        "The attack handler cannot compile without it.")

server_env = read(ROOT / "server.env")
if not re.search(r"^\s*NWNX_DAMAGE_SKIP=n\s*$", server_env, re.M):
    errors.append(
        "server.env does not set NWNX_DAMAGE_SKIP=n — the Damage plugin will "
        "not load and every NWNX_Damage_* call fails with 'Plugin not loaded'.")

# --- 2. handlers registered -------------------------------------------------
modload = read(UNPACKED / "onmoduleload.nss")

if 'NWNX_Damage_SetAttackEventScript("devcrit_atk")' not in modload:
    errors.append(
        'onmoduleload.nss does not call '
        'NWNX_Damage_SetAttackEventScript("devcrit_atk") — the bonus damage '
        "never fires.")

if not re.search(r"NWNX_Events_SubscribeEvent\(\s*NWNX_ON_EFFECT_APPLIED_BEFORE\s*,"
                 r'\s*"devcrit_eff"\s*\)', modload):
    errors.append(
        "onmoduleload.nss does not subscribe devcrit_eff to "
        "NWNX_ON_EFFECT_APPLIED_BEFORE — devastating criticals would add the "
        "bonus damage AND still kill outright.")

if '#include "nwnx_damage"' not in modload:
    errors.append('onmoduleload.nss is missing #include "nwnx_damage".')

for name in ("devcrit_atk.nss", "devcrit_eff.nss", "devcrit_inc.nss"):
    if not (UNPACKED / name).is_file():
        errors.append(f"unpacked/{name} is missing.")

# --- 3. the hot-path guard --------------------------------------------------
atk = read(UNPACKED / "devcrit_atk.nss")

# Strip comments so a guard that only exists in prose cannot satisfy this.
atk_code = re.sub(r"//[^\n]*", "", atk)
body = atk_code.split("void main()", 1)[-1]
statements = [s.strip() for s in body.split(";") if s.strip()]

guard = next((i for i, s in enumerate(statements)
              if "iAttackResult" in s or "nResult != 3" in s), None)
if guard is None:
    errors.append(
        "devcrit_atk.nss has no iAttackResult guard — it would do work on "
        "every single attack on the server.")
elif guard > 3:
    errors.append(
        f"devcrit_atk.nss does {guard} statements of work before its "
        "iAttackResult guard. That guard must come first: this script runs on "
        "every attack on the server.")

if "return" not in "".join(statements[:guard + 2] if guard is not None else []):
    errors.append(
        "devcrit_atk.nss's iAttackResult guard does not return — a "
        "non-critical attack must leave the script immediately.")

# --- 4. the death-effect discrimination -------------------------------------
eff = re.sub(r"//[^\n]*", "", read(UNPACKED / "devcrit_eff.nss"))

if "DEVCRIT_EFFTYPE_DEATH" not in eff:
    errors.append(
        "devcrit_eff.nss does not test DEVCRIT_EFFTYPE_DEATH — it must only "
        "look at death effects.")

if "DevCrit_IsNoKill" not in eff:
    errors.append(
        "devcrit_eff.nss does not test DevCrit_IsNoKill — without the attack "
        "handler's flag it would suppress EVERY death effect in the module "
        "(Finger of Death, Death Attack, scripted deaths, DM kills).")

if "NWNX_Events_SkipEvent" not in eff:
    errors.append("devcrit_eff.nss never calls NWNX_Events_SkipEvent.")

# --- 5. code matches the published design -----------------------------------
inc = read(UNPACKED / "devcrit_inc.nss")


def const(name):
    match = re.search(rf"const\s+int\s+{name}\s*=\s*(\d+)\s*;", inc)
    return int(match.group(1)) if match else None


EXPECTED = {
    "DEVCRIT_DICE": 3,          # Devastating Critical
    "DEVCRIT_DICE_BUTCH": 5,    # Legendary Butcher, stacking
    "DEVCRIT_DIE_SMALL": 6,
    "DEVCRIT_DIE_MEDIUM": 8,
    "DEVCRIT_DIE_LARGE": 10,
    "DEVCRIT_EFFTYPE_DEATH": 19,  # NWNXLib Constants/Effect.hpp EffectTrueType
}
for name, want in EXPECTED.items():
    got = const(name)
    if got is None:
        errors.append(f"devcrit_inc.nss does not define {name}.")
    elif got != want:
        errors.append(
            f"devcrit_inc.nss {name} is {got}, expected {want}. These are the "
            "numbers published on the roadmap (devcrit-roll) and shown to "
            "players; change both together, or the design and the code have "
            "drifted.")

# The roadmap card is the published half of the same numbers.
roadmap = read(ROOT / "roadmap.yaml")
if "- id: devcrit-roll" not in roadmap:
    errors.append("roadmap.yaml has no devcrit-roll entry.")
else:
    card = roadmap.split("- id: devcrit-roll", 1)[1].split("\n  - id: ", 1)[0]
    for phrase in ("+3 dice", "+5 dice"):
        if phrase not in card:
            errors.append(
                f"roadmap.yaml's devcrit-roll card no longer says '{phrase}' — "
                "if the dice changed, change devcrit_inc.nss and the expected "
                "values in this gate too.")

# --- 6. the save-or-die is disabled at source -------------------------------
COLUMN = "EpicWeaponDevastatingCriticalFeat"
baseitems = (ROOT / "hak_2da" / "baseitems.2da")
if not baseitems.is_file():
    errors.append("hak_2da/baseitems.2da is missing.")
else:
    lines = baseitems.read_bytes().decode("latin-1").replace(
        "\r\n", "\n").split("\n")
    header = next((ln.split() for ln in lines if COLUMN in ln), None)
    if header is None:
        errors.append(f"hak_2da/baseitems.2da has no {COLUMN} column.")
    else:
        col = header.index(COLUMN) + 1   # +1: the row number precedes the header
        named = []
        for ln in lines:
            fields = ln.split()
            if len(fields) <= col or not fields[0].isdigit():
                continue
            if fields[col].isdigit():
                named.append(fields[0])
        if named:
            errors.append(
                f"hak_2da/baseitems.2da still names a devastating critical feat "
                f"on {len(named)} row(s) (e.g. base item {named[0]}). The "
                "engine's save-or-die is live again for those weapons — re-run "
                "python3 bin/gen-devcrit-map.py --apply, then rebuild the hak.")

    map_inc = UNPACKED / "devcrit_map_inc.nss"
    if not map_inc.is_file():
        errors.append(
            "unpacked/devcrit_map_inc.nss is missing — generate it with "
            "python3 bin/gen-devcrit-map.py --apply. Without it devcrit_inc.nss "
            "does not compile.")
    else:
        cases = re.findall(r"case\s+\d+:\s*return\s+\d+;",
                           map_inc.read_text(encoding="latin-1"))
        if len(cases) < 60:
            errors.append(
                f"unpacked/devcrit_map_inc.nss maps only {len(cases)} base "
                "items to a devastating critical feat (expected the full stock "
                "+ CEP set, ~67). The bonus dice would silently stop firing for "
                "the missing weapons.")

if "DevCrit_HasDevCrit" not in read(UNPACKED / "devcrit_inc.nss"):
    errors.append(
        "devcrit_inc.nss no longer defines DevCrit_HasDevCrit — with the "
        "engine's check disabled, the feat test is the ONLY thing that grants "
        "the bonus dice.")

# ---------------------------------------------------------------------------
if errors:
    print("check_devcrit: FAIL")
    for err in errors:
        print(f"  - {err}")
    sys.exit(1)

print("check_devcrit: ok (NWNX Damage enabled, both handlers wired, "
      "dice match the published design)")
sys.exit(0)
