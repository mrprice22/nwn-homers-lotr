#!/usr/bin/env python3
"""Build gate: the Combat Dummy (roadmap combat-dummy) is wired end to end.

The dummy measures attacks and damage per round. Every way it can break is
silent — it keeps standing there, players keep hitting it, and the numbers are
just wrong or never appear:

  1. The APR half rides in devcrit_atk.nss, the GLOBAL NWNX attack handler. If
     that hook is dropped (or moved behind devcrit's critical-hit guard, which
     returns on every non-critical attack), attacks per round silently reports
     zero or counts only criticals — and the whole point of the feature is
     measuring feats that add ordinary attacks.
  2. The DPR half and the indestructibility both live in cbd_damage.nss, which
     only runs because cbd_spawn registers it PER OBJECT. Lose the registration
     and the dummy takes real damage and dies; lose the zeroing and Harm/Drown
     kill it.
  3. The blueprint has to stay hostile (so hostile-only spells can target it)
     and has to keep pointing at cbd_spawn/cbd_death, or a toolset-placed dummy
     installs nothing at all.
"""
import json
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


def strip_comments(src):
    return re.sub(r"//[^\n]*", "", src)


# --- 1. every piece exists --------------------------------------------------
required = [
    "cbd_inc.nss", "cbd_db.nss", "cbd_spawn.nss", "cbd_damage.nss",
    "cbd_death.nss", "cbd_use.nss", "cbd_mode_1.nss", "cbd_mode_2.nss",
    "cbd_mode_3.nss", "cbd_page_n.nss", "cbd_page_p.nss", "cbd_has_next.nss",
    "cbd_has_prev.nss", "cbd_dummy.utc.json", "cbd_sign.utp.json",
    "cbd_sign.dlg.json",
]
for name in required:
    if not (UNPACKED / name).is_file():
        errors.append(f"unpacked/{name} is missing.")

# --- 2. the attack hook, ahead of devcrit's critical guard ------------------
atk = strip_comments(read(UNPACKED / "devcrit_atk.nss"))
if "CBD_TrackAttack" not in atk:
    errors.append(
        "devcrit_atk.nss no longer calls CBD_TrackAttack — attacks per round "
        "would always read zero. That global attack event is the only place a "
        "MISS is visible, so the count cannot be taken anywhere else.")
else:
    body = atk.split("void main()", 1)[-1]
    stmts = [s.strip() for s in body.split(";") if s.strip()]
    hook = next((i for i, s in enumerate(stmts) if "CBD_TrackAttack" in s), None)
    crit = next((i for i, s in enumerate(stmts) if "iAttackResult" in s), None)
    if hook is not None and crit is not None and hook > crit + 1:
        errors.append(
            "devcrit_atk.nss calls CBD_TrackAttack after its critical-hit "
            "guard has already returned — only criticals would be counted.")
    if hook is not None and "GetLocalInt" not in "".join(stmts[:hook + 1]):
        errors.append(
            "the CBD_TrackAttack call in devcrit_atk.nss is not behind a "
            "GetLocalInt guard — it runs on every attack on the server.")

# --- 3. the per-object damage handler ---------------------------------------
spawn = strip_comments(read(UNPACKED / "cbd_spawn.nss"))
if 'NWNX_Damage_SetDamageEventScript("cbd_damage"' not in spawn:
    errors.append(
        "cbd_spawn.nss does not register cbd_damage per object — the dummy "
        "would take real damage, die, and record nothing.")
if "EffectCutsceneImmobilize" not in spawn:
    errors.append("cbd_spawn.nss no longer immobilizes the dummy.")
if "IMMUNITY_TYPE_DEATH" not in spawn:
    errors.append(
        "cbd_spawn.nss no longer grants death immunity — damage is zeroed, but "
        "death EFFECTS are not damage and would still drop the dummy.")

dmg = strip_comments(read(UNPACKED / "cbd_damage.nss"))
if "NWNX_Damage_SetDamageEventData" not in dmg:
    errors.append(
        "cbd_damage.nss never writes the damage back — without "
        "NWNX_Damage_SetDamageEventData the zeroing does nothing and the dummy "
        "is destructible.")
for field in ("iBludgeoning", "iNegative", "iCustom19"):
    if not re.search(rf"data\.{field}\s*=\s*0", dmg):
        errors.append(
            f"cbd_damage.nss does not zero data.{field} — one live damage type "
            "is enough for Harm or a drown to kill the dummy.")

# --- 4. the blueprint still says what the scripts assume --------------------
utc_path = UNPACKED / "cbd_dummy.utc.json"
if utc_path.is_file():
    utc = json.loads(utc_path.read_text(encoding="latin-1"))

    def val(field):
        return utc.get(field, {}).get("value")

    if val("FactionID") != 1:
        errors.append(
            f"cbd_dummy.utc.json FactionID is {val('FactionID')}, not 1 "
            "(Hostile) — hostile-only spells such as Isaac's Greater Missile "
            "Storm could not target the dummy.")
    if val("ScriptSpawn") != "cbd_spawn":
        errors.append(
            "cbd_dummy.utc.json ScriptSpawn is not cbd_spawn — a dummy placed "
            "from the toolset would install nothing.")
    if val("ScriptDeath") != "cbd_death":
        errors.append(
            "cbd_dummy.utc.json ScriptDeath is not cbd_death — a destroyed "
            "dummy would never come back.")
    if val("Plot") != 0:
        errors.append(
            "cbd_dummy.utc.json is flagged Plot. It must NOT be: the engine "
            "zeroes damage to a plot creature BEFORE the NWNX damage event, so "
            "every attack measures 0, DPR reads 0 and nothing is ever written "
            "to the leaderboard. This is exactly what the first UAT hit. "
            "Indestructibility comes from cbd_damage zeroing the damage after "
            "counting it, not from the Plot flag.")

utp_path = UNPACKED / "cbd_sign.utp.json"
if utp_path.is_file():
    utp = json.loads(utp_path.read_text(encoding="latin-1"))
    if utp.get("Conversation", {}).get("value") != "cbd_sign":
        errors.append("cbd_sign.utp.json does not point at the cbd_sign "
                      "conversation.")
    if utp.get("OnUsed", {}).get("value") != "cbd_use":
        errors.append("cbd_sign.utp.json OnUsed is not cbd_use — the sign "
                      "would open with empty tokens.")

# --- 5. the abandoned-session watchdog --------------------------------------
inc = strip_comments(read(UNPACKED / "cbd_inc.nss"))
if "CBD_Watchdog" not in inc or "CBD_IDLE_LIMIT" not in inc:
    errors.append(
        "cbd_inc.nss has no idle watchdog — a tester who wanders off mid-trial "
        "would still have ten rounds counted, most of them empty, and that "
        "score would be written to the leaderboard.")
if "GetArea(oPC) != GetArea(oDummy)" not in inc:
    errors.append(
        "cbd_inc.nss's watchdog no longer cancels when the owner leaves the "
        "area.")
if "CBD_Touch" not in strip_comments(read(UNPACKED / "cbd_damage.nss")):
    errors.append(
        "cbd_damage.nss never calls CBD_Touch — the idle clock would never "
        "reset for a caster, and a spell-only trial would be cancelled "
        "mid-run.")

# --- 6. the reports survive the float fading --------------------------------
if "SpeakString" not in inc:
    errors.append(
        "cbd_inc.nss no longer speaks its reports. Floating text fades in "
        "seconds; the spoken copy is what puts the round figures and the final "
        "averages in the chat log where they can be scrolled back to, which is "
        "the entire point of the readout.")
if "SendMessageToPC" not in inc:
    errors.append("cbd_inc.nss no longer sends its reports to the chat log.")

# --- 7. the sign's tokens and the conversation agree ------------------------
db = read(UNPACKED / "cbd_db.nss")
dlg_src = read(UNPACKED / "cbd_sign.dlg.json")
for tok in [6400] + list(range(6401, 6411)) + [6411]:
    if f"<CUSTOM{tok}>" not in dlg_src:
        errors.append(
            f"cbd_sign.dlg.json never shows <CUSTOM{tok}>, but cbd_db.nss "
            "fills it — that leaderboard row would be invisible.")

# --- 8. the end-of-set self-destruct ----------------------------------------
# A finished set ends with the dummy blowing apart and the tester's actions
# cancelled. Both are the STOP cue: without them a tester keeps swinging into
# the cooldown and reads the next session's opening rounds as part of this one.
if "CBD_SelfDestruct" not in inc:
    errors.append(
        "cbd_inc.nss no longer defines CBD_SelfDestruct — a completed 10-round "
        "set must end with the dummy destroying itself; that visual and the "
        "cbd_death respawn are the end-of-set cue.")
else:
    destruct = inc.split("void CBD_SelfDestruct(object oDummy, object oPC,", 1)[-1]
    destruct = destruct.split("void CBD_EndSession", 1)[0]
    if "ClearAllActions" not in destruct:
        errors.append(
            "CBD_SelfDestruct does not ClearAllActions on the session owner — "
            "the tester keeps attacking after the set is over.")
    if "EffectDeath" not in destruct:
        errors.append("CBD_SelfDestruct never applies EffectDeath.")
    if "EFFECT_TYPE_IMMUNITY" not in destruct:
        errors.append(
            "CBD_SelfDestruct does not strip the death immunity cbd_spawn "
            "applies, so the kill it asks for cannot land and the set ends "
            "with no cue at all.")

if "CBD_SelfDestruct" not in inc.split("void CBD_EndSession", 1)[-1]:
    errors.append(
        "CBD_EndSession never schedules CBD_SelfDestruct — the set would end "
        "silently.")

# The dummy must still be indestructible for the other 10 rounds.
if "IMMUNITY_TYPE_DEATH" not in strip_comments(read(UNPACKED / "cbd_spawn.nss")):
    errors.append(
        "cbd_spawn.nss no longer grants death immunity — the dummy could die "
        "mid-set, which throws the run away.")

if errors:
    print("check_combat_dummy: FAIL")
    for e in errors:
        print("  - " + e)
    sys.exit(1)

print("check_combat_dummy: ok")
