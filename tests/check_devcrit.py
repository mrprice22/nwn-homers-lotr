#!/usr/bin/env python3
"""Build gate: the Devastating Critical rework (roadmap devcrit-roll) is wired.

unpacked/devcrit_atk.nss runs on EVERY attack on the server. A mistake in it is
a mistake in all combat, and every failure mode is silent: the plugin simply is
not loaded, or the handler is not registered, or the guard that makes the hot
path cheap has been edited away, and combat carries on looking normal while the
feature does nothing. This checks the things that cannot be seen from the game.

  1. Both halves of enabling the plugin moved together: the include is in
     unpacked/ AND server.env sets NWNX_DAMAGE_SKIP=n. Copying the include
     without the env flip gives per-call "Plugin not loaded" errors and nothing
     else.
  2. onmoduleload.nss registers the attack handler, and the scripts exist.
  3. devcrit_atk.nss still returns early on anything that is not a critical,
     before it does any other work.
  4. The unarmed/creature half of the kill is still disabled (roadmap
     devcrit-unarmed-save-or-die). Those two feats are the only devastating
     criticals the engine resolves WITHOUT reading baseitems.2da, so blanking
     the column cannot reach them and DevCrit_ArmNoDevCrit stripping the feat
     is the only thing that stops the save-or-die for a fist build. Checks the
     helper exists, that it is armed from login, level-up AND creature spawn,
     that the dice still ride on the snapshot it leaves behind, and that
     LegFeat_HasAnyDevCrit reads the same two local names — a typo there costs
     every monk the Legendary Butcher prerequisite, silently.
  5. The published numbers in roadmap.yaml's devcrit-roll card still match the
     constants in devcrit_inc.nss, so the code and the player-facing design
     cannot drift apart.
  6. The save-or-die is still disabled AT SOURCE for weapon attacks:
     hak_2da/baseitems.2da's EpicWeaponDevastatingCriticalFeat column is blank
     on every row, and the mapping it used to hold still exists in the generated
     unpacked/devcrit_map_inc.nss. Either half alone is a silent failure — a
     re-extracted baseitems.2da brings the instant kill back, and an empty
     include takes the replacement dice away from every weapon.

devcrit_eff.nss (an NWNX_ON_EFFECT_APPLIED_BEFORE subscriber that tried to
refuse the engine's death effect) was deleted along with its section of this
gate: UAT proved it never caught the kill, and as a per-effect global hook it
was charged with TOO MANY INSTRUCTIONS whenever an unrelated script overran its
VM budget.
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

if re.search(r"NWNX_Events_SubscribeEvent\(\s*NWNX_ON_EFFECT_APPLIED_BEFORE\s*,"
             r'\s*"devcrit_eff"\s*\)', modload):
    errors.append(
        "onmoduleload.nss still subscribes devcrit_eff to "
        "NWNX_ON_EFFECT_APPLIED_BEFORE. That handler was deleted: it never "
        "caught the engine's kill, and a per-effect global hook is charged "
        "with TOO MANY INSTRUCTIONS every time any other script overruns.")

if '#include "nwnx_damage"' not in modload:
    errors.append('onmoduleload.nss is missing #include "nwnx_damage".')

for name in ("devcrit_atk.nss", "devcrit_arm.nss", "devcrit_inc.nss"):
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

# --- 4. the unarmed / creature half -----------------------------------------
# Comments stripped throughout: a check that prose alone can satisfy is no check.
inc = read(UNPACKED / "devcrit_inc.nss")
inc_code = re.sub(r"//[^\n]*", "", inc)

# The two snapshot names are the contract between devcrit_inc.nss and the
# GENERATED legfeat_ids_inc.nss, which has no includes and must repeat them as
# literals. A drift here is silent in both directions.
snapshot_names = {}
for const_name, expected in (("DEVCRIT_VAR_HAD_UNARMED", "DEVCRIT_HAD_UNARMED"),
                             ("DEVCRIT_VAR_HAD_CREATURE", "DEVCRIT_HAD_CREATURE")):
    match = re.search(rf'const\s+string\s+{const_name}\s*=\s*"([^"]*)"\s*;', inc_code)
    if not match:
        errors.append(
            f"devcrit_inc.nss no longer defines {const_name} — the snapshot is "
            "what keeps the replacement dice after the feat is stripped.")
    else:
        snapshot_names[const_name] = match.group(1)
        if match.group(1) != expected:
            errors.append(
                f"{const_name} is \"{match.group(1)}\", not \"{expected}\". "
                "legfeat_ids_inc.nss repeats these as literals (it has no "
                "includes); change bin/gen-legendary-feats.py in the same "
                "commit or every monk silently loses the Legendary Butcher "
                "prerequisite.")

if "NWNX_Creature_RemoveFeat" not in inc_code:
    errors.append(
        "devcrit_inc.nss no longer calls NWNX_Creature_RemoveFeat. Stripping "
        "FEAT_EPIC_DEVASTATING_CRITICAL_UNARMED / _CREATURE is the ONLY thing "
        "that stops the save-or-die on an unarmed or creature-weapon attack — "
        "the engine resolves those without reading baseitems.2da, so the blank "
        "column cannot reach them (roadmap devcrit-unarmed-save-or-die).")

if not re.search(r"^\s*NWNX_CREATURE_SKIP=n\s*$", server_env, re.M):
    errors.append(
        "server.env does not set NWNX_CREATURE_SKIP=n — NWNX_Creature_RemoveFeat "
        "fails with 'Plugin not loaded' and the unarmed save-or-die comes back.")

for path, why in (
        ("mod_cliententer.nss", "a player logging in keeps the feat"),
        ("legfeat_lvl.nss",
         "a level-up hands the feat back — the engine offers a feat the "
         "character no longer holds, so it can be re-picked"),
        ("nw_c2_default9.nss", "every NPC that spawns keeps the feat")):
    hook = re.sub(r"//[^\n]*", "", read(UNPACKED / path))
    armed = ("DevCrit_ArmNoDevCrit" in hook) or ('"devcrit_arm"' in hook)
    if not armed:
        errors.append(
            f"unpacked/{path} does not arm DevCrit_ArmNoDevCrit — {why}, and "
            "its devastating criticals still kill outright.")

# The dice must ride on the snapshot, not on a feat that has just been removed.
for helper in ("DevCrit_HadUnarmed", "DevCrit_HadCreature"):
    if f"return {helper}(oAttacker)" not in inc_code:
        errors.append(
            f"DevCrit_HasDevCrit no longer resolves through {helper}. Once the "
            "feat is stripped, GetHasFeat alone returns FALSE and the "
            "replacement dice quietly stop paying out for fists and claws.")

legfeat_ids = re.sub(r"//[^\n]*", "", read(UNPACKED / "legfeat_ids_inc.nss"))
for const_name, literal in snapshot_names.items():
    if f'GetLocalInt(oPC, "{literal}")' not in legfeat_ids:
        errors.append(
            f'legfeat_ids_inc.nss (GENERATED) does not read "{literal}" in '
            "LegFeat_HasAnyDevCrit — regenerate it with "
            "bin/gen-legendary-feats.py --apply. Without it, stripping the feat "
            "costs the character the Legendary Butcher prerequisite.")

# The alarm must not be behind the debug flag: it fires on a live realm, days
# before anyone reads the log, and it is the whole diagnosis in one line.
if "DevCrit_AlarmEngineCrit" not in atk_code:
    errors.append(
        "devcrit_atk.nss no longer calls DevCrit_AlarmEngineCrit on "
        "iAttackResult 10. That branch is meant to be unreachable; if it ever "
        "runs it is the only evidence of which lookup leaked.")
if "WriteTimestampedLogEntry" not in inc_code:
    errors.append(
        "DevCrit_AlarmEngineCrit no longer writes to the server log — a "
        "message to whoever is online is not a record.")

# --- 5. code matches the published design -----------------------------------


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

print("check_devcrit: ok (NWNX Damage enabled, attack handler wired, "
      "unarmed/creature feats stripped at login+level-up+spawn, "
      "dice match the published design)")
sys.exit(0)
