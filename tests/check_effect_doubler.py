#!/usr/bin/env python3
"""Build gate: the spell-duration doubler re-applies a LINKED effect as a link.

unpacked/eff_dur_x2.nss re-times an effect by removing it and re-applying a copy.
A linked effect surfaces as several true-effects that ALL SHARE ONE id, and
NWNX_Effect_RemoveEffectById removes every one of them - so the copy has to be
rebuilt from ALL the components sharing that id. Re-applying just one is not a
partial fix, it is destruction: N components go in, 1 comes back, the other N-1
are gone.

That is not hypothetical. It shipped, and it took out four abilities at once:
Curse Song collapsed to nothing but its attack decrease, Bard Song to the two
bonuses the ledger applies OUTSIDE the link, and Taunt and Wounding Whispers to
nothing at all (reported by -Methonash- and Sync). The same corruption is behind
roadmap improved-invis-issues-part2, and the per-spell exclusion lists in that
script are patches over it.

This is a gate rather than a review note for the usual reason: the broken version
compiles, runs, logs a cheerful "doubled" line, and the only symptom is that an
ability quietly does less than it says. Nothing in the build notices, and the
player who notices cannot tell you which script did it.

Also note NWNX_Effect_GetTrueEffect resolves with __NWNX_Effect_ResolveUnpack(FALSE)
- bLink = FALSE - so each component arrives with its link fields cleared. The link
genuinely cannot be recovered from a single component; it has to be rebuilt.

A rebuilt link also has to be given the ORIGINAL EFFECT'S IDENTITY back. The
parent effect EffectLinkEffects builds is created here, in a delayed script with
no spell context, and the engine hands the parent's creator/spell id/subtype down
to its children - so a faithful per-component copy still comes back out as "spell
-1, cast by nobody". Everything that identifies an effect by its spell then stops
seeing it: the bonus ledger's witness check (bonus_pool_inc.nss), the songs'
"already sung on" guards, RemoveSpellEffects, dispel attribution. That is roadmap
bard-song-issues-round-2 - Bard Song and War Cry lost their attack bonus one
second after every application, while every other part of the same buff worked.

Checks:
  1. The doubler links its components back together (EffectLinkEffects).
  2. The apply is fed the accumulated link, not a single packed component.
  3. The collect loop has no `break` - every component sharing the id must be
     visited, both to rebuild the link and to honour the link-sensitive guard.
  4. The rebuilt link is re-stamped with the original nSpellId and oCreator
     before it is applied.
"""
import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
SRC = ROOT / "unpacked" / "eff_dur_x2.nss"

errors = []

if not SRC.exists():
    print(f"check_effect_doubler: FAIL: {SRC} is missing", file=sys.stderr)
    sys.exit(1)

text = SRC.read_text(encoding="utf-8", errors="replace")

# Strip // comments so prose about the bug cannot satisfy the checks.
code = "\n".join(re.sub(r"//.*$", "", ln) for ln in text.splitlines())

# 1. the components are re-linked
if "EffectLinkEffects" not in code:
    errors.append(
        "eff_dur_x2.nss never calls EffectLinkEffects. A linked effect's components "
        "all share one id and RemoveEffectById takes all of them, so re-applying "
        "without rebuilding the link destroys every component but one.")

# 2. the apply is fed the accumulation, not one component
m = re.search(r"ApplyEffectToObject\s*\(\s*DURATION_TYPE_TEMPORARY\s*,\s*(\w+)", code)
if not m:
    errors.append(
        "eff_dur_x2.nss has no ApplyEffectToObject(DURATION_TYPE_TEMPORARY, ...) - "
        "the re-apply is how the doubled duration is delivered.")
else:
    applied = m.group(1)
    linked = set(re.findall(r"(\w+)\s*=\s*EffectLinkEffects\s*\(", code))
    if applied not in linked:
        errors.append(
            f"eff_dur_x2.nss re-applies '{applied}', which is never built by "
            f"EffectLinkEffects (built: {sorted(linked) or 'nothing'}). That is the "
            "single-component re-apply that destroys linked effects.")

# 3. no early exit from the collect loop
collect = re.search(r"for\s*\(\s*i\s*=\s*0;\s*i\s*<\s*nCount;.*?\n\s*\}", code, re.S)
if not collect:
    errors.append("eff_dur_x2.nss has no `for (i = 0; i < nCount; ...)` collect loop.")
elif re.search(r"^\s*break\s*;", collect.group(0), re.M):
    errors.append(
        "the collect loop in eff_dur_x2.nss breaks early. Every component sharing the "
        "id must be visited - both to rebuild the link and so the link-sensitive guard "
        "sees a sibling that is not the first match.")

# 4. the rebuilt link gets its identity back before the apply
if "NWNX_Effect_UnpackEffect" not in code:
    errors.append(
        "eff_dur_x2.nss never unpacks the rebuilt link. The link EffectLinkEffects "
        "builds carries no spell id or creator of its own, and the engine hands the "
        "parent's identity down to the components - so the re-applied buff answers "
        "GetHasSpellEffect() for nothing. Unpack the finished link, write nSpellId "
        "and oCreator back onto it, and re-pack before applying.")
else:
    restamp = re.search(
        r"(\w+)\s*=\s*NWNX_Effect_UnpackEffect\s*\(\s*(\w+)\s*\)\s*;(.*?)"
        r"\2\s*=\s*NWNX_Effect_PackEffect\s*\(\s*\1\s*\)",
        code, re.S)
    if not restamp:
        errors.append(
            "eff_dur_x2.nss unpacks the rebuilt link but never packs it back into the "
            "effect it applies - the identity re-stamp is incomplete.")
    else:
        struct_var, body = restamp.group(1), restamp.group(3)
        for field in ("nSpellId", "oCreator"):
            if not re.search(rf"{struct_var}\s*\.\s*{field}\s*=", body):
                errors.append(
                    f"eff_dur_x2.nss does not restore .{field} on the rebuilt link. "
                    "Without it the re-applied buff loses the identity every "
                    "GetHasSpellEffect() consumer keys off.")

if errors:
    print("check_effect_doubler: FAIL", file=sys.stderr)
    for e in errors:
        print(f"  - {e}", file=sys.stderr)
    sys.exit(1)

print("check_effect_doubler: ok (linked effects are re-applied as links, identity intact)")
