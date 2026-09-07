#!/usr/bin/env python3
"""Build gate: the overridden BioWare AI never turns a creature on its own faction.

The module overrides four of BioWare's default AI scripts. Three of them had lost
(or never had) the same-faction guard that stops a creature retaliating against an
ally, and the result was the defect Rajmund (Ray) and -Methonash- reported in the
Weathertop court: archers shooting other archers (roadmap
wtop-court-combat-defects).

The failure is a two-stage one, which is why all four files are gated together:

  IGNITION  nw_c2_default6 (OnDamaged) / nw_c2_default5 (OnAttacked) retarget onto
            whoever damaged us when `(GetHitDice(oDamager) - 2) > GetHitDice(oTarget)`.
            For a CR-200 garrison fighting a player that test is ALWAYS true, so a
            single point of splash damage from an ally flipped a unit onto its own
            side.

  EXPLOSION nw_i0_generic's NW_ATTACK_MY_TARGET shout (case 5) then called
            AdjustReputation(oIntruder, OBJECT_SELF, -100) with no friend test.
            Between two NPCs that is a FACTION-to-faction edit: one call naming an
            ally drops Hostile->Hostile to 0 and every hostile creature in the
            module turns on every other one, for the rest of the server session.
            The shout is emitted on every attack (nw_c2_default5) and every death
            (nw_c2_default7), so the collapse spreads on its own.

  WRONG OBJECT nw_c2_default4 resolved that shout's intruder with
            GetAttemptedAttackTarget()/GetAttemptedSpellTarget() as fallbacks. Those
            take no object argument, so they answer for OBJECT_SELF - the creature
            LISTENING to the shout, not the shouter - and the listener fed its own
            current target in as the "intruder". No target is better than the wrong
            one.

This is a gate rather than a comment because these four files are stock BioWare
sources kept in the module as overrides: the obvious way to fix an unrelated bug in
one of them is to re-copy the stock file, which silently removes the guards again.
The symptom is also invisible to the build - the module compiles, the encounter
runs, and the only sign is that a fight looks wrong hours later on a realm nobody
has rebooted.

Checks (comments stripped first, so prose about the bug cannot satisfy them):
  1. nw_c2_default5 neutralises a same-faction attacker before using it.
  2. nw_c2_default6 neutralises a same-faction damager before using it.
  3. nw_i0_generic's case 5 bails out on an invalid, same-faction or friendly
     intruder, and only adjusts reputation against a PC.
  4. nw_c2_default4 does not fall back to the argument-less attempted-target
     functions when resolving a shout's intruder.
"""
import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
SRC = ROOT / "unpacked"

errors = []


def code_of(name):
    path = SRC / name
    if not path.exists():
        errors.append(f"{name} is missing from unpacked/")
        return None
    text = path.read_text(encoding="utf-8", errors="replace")
    return "\n".join(re.sub(r"//.*$", "", ln) for ln in text.splitlines())


def guarded(code, var):
    """The variable is cleared when it turns out to be one of ours."""
    return re.search(
        rf"GetFactionEqual\s*\(\s*{var}\b.*?{var}\s*=\s*OBJECT_INVALID",
        code, re.S) is not None


# 1 + 2. the two retarget paths
for name, var, event in (("nw_c2_default5.nss", "oAttacker", "OnAttacked"),
                         ("nw_c2_default6.nss", "oDamager", "OnDamaged")):
    code = code_of(name)
    if code is None:
        continue
    if not guarded(code, var):
        errors.append(
            f"{name} ({event}) does not neutralise a same-faction {var}. Expected a "
            f"GetFactionEqual({var}, OBJECT_SELF) test that sets {var} = OBJECT_INVALID "
            "before the retarget. Without it one point of ally damage turns a creature "
            "on its own side.")

# 3. the shout responder
code = code_of("nw_i0_generic.nss")
if code is not None:
    case5 = re.search(r"case\s+5\s*:(.*?)\bbreak\s*;\s*\n\s*case\b", code, re.S)
    if not case5:
        errors.append(
            "nw_i0_generic.nss has no `case 5:` (ATTACK MY TARGET) in the shout "
            "responder - the gate cannot verify the guard that keeps a faction intact.")
    else:
        body = case5.group(1)
        if not ("GetFactionEqual" in body and "GetIsFriend(oIntruder)" in body):
            errors.append(
                "nw_i0_generic.nss case 5 (ATTACK MY TARGET) does not bail out on an "
                "invalid, same-faction or friendly intruder. AdjustReputation between "
                "two NPCs is a faction-level edit: one unguarded call sets every hostile "
                "creature in the module against every other one for the whole session.")
        adjust = re.search(r"AdjustReputation\s*\(\s*oIntruder", body)
        if adjust and "GetIsPC(oIntruder)" not in body[:adjust.start()]:
            errors.append(
                "nw_i0_generic.nss case 5 calls AdjustReputation(oIntruder, ...) without "
                "first establishing that the intruder is a PC. Personal reputation "
                "against a player is what this case is for; a faction-level edit aimed "
                "at an NPC never is.")

# 4. the shout's intruder must not be resolved off the listener
code = code_of("nw_c2_default4.nss")
if code is not None:
    if re.search(r"oIntruder\s*=\s*GetAttempted(Attack|Spell)Target\s*\(\s*\)", code):
        errors.append(
            "nw_c2_default4.nss resolves a shout's intruder with "
            "GetAttemptedAttackTarget()/GetAttemptedSpellTarget(). Those take no object "
            "argument, so they answer for OBJECT_SELF - the creature listening to the "
            "shout - and it ends up naming its own target as the intruder. Use only "
            "GetLastHostileActor(oShouter) and leave oIntruder invalid otherwise.")

if errors:
    print("check_ai_faction_guards: FAIL", file=sys.stderr)
    for e in errors:
        print(f"  - {e}", file=sys.stderr)
    sys.exit(1)

print("check_ai_faction_guards: ok (the default AI cannot turn a creature on its own faction)")
