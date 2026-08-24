#!/usr/bin/env python3
"""Encounter cache coherence check (build-time smoke test).

Encounters in this module get no scripting at all -- every instance has empty
OnEntered/OnExhausted/OnHeartbeat, there are no nw_e0_* overrides, and nothing
spawns their creatures but the engine. That makes the stored GFF fields the
whole of the behaviour, and two of those fields are caches that drift:

  * each creature-list entry caches the blueprint's ChallengeRating in its `CR`,
    written once by the toolset when the creature was added to the list;
  * `Difficulty` caches encdifficulty.2da's VALUE for the encounter's
    `DifficultyIndex` row (VeryEasy=0 Easy=1 Normal=2 Hard=5 Impossible=9).

Neither is refreshed when its source changes, and nothing in the build noticed.
That is how `spidgiant001` came to be cached at CR 147 while its blueprint says
21: the engine fills an encounter high->low against a CR budget, so it spent
almost the whole budget on a creature it believed was the toughest in the pool
and was really a trash mob, and the CR-45 spiders behind it never spawned. Same
shape in Dimholt, where the Thing of the Dark stopped appearing. Player report
`encounter-spawns-levels-41-60`.

The invariant this enforces:

    an encounter's cached CR equals its creature blueprint's ChallengeRating,
    and its Difficulty equals encdifficulty.2da[DifficultyIndex].

Both halves come straight from bin/audit-encounter-crs.py -- this gate imports
its scan() rather than re-deriving anything, so the gate and the fixer can never
disagree (same arrangement as tests/check_map_notes.py and bin/gen-map-notes.py).

Deliberately NOT failures:

  * entries whose resref has no .utc.json -- 171 encounter resrefs are stock
    base-game creatures (nw_*, x2_*, zep_*) that live in the game data, not
    unpacked/, so there is no local blueprint to compare against;
  * a DifficultyIndex outside 0-4 -- not a cache disagreement, and nothing the
    fixer could resolve.

This gate never asks for a blueprint ChallengeRating to change. That value is
read live on every kill for XP, gold, the bestiary and the boss board's CR > 60
rule; only the encounter's copy of it is in scope here.

Exits 0 when both caches are coherent, 1 otherwise (prints offenders and the
exact command that fixes them).
"""

import importlib.util
import os
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
TOOL = os.path.join(ROOT, "bin", "audit-encounter-crs.py")
FIX = "python3 bin/audit-encounter-crs.py --apply"

MAX_SHOWN = 12


def load_tool():
    """Import bin/audit-encounter-crs.py (hyphens make it non-importable by name)."""
    spec = importlib.util.spec_from_file_location("audit_encounter_crs", TOOL)
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


def show(issues, render):
    for issue in issues[:MAX_SHOWN]:
        print(f"    {render(issue)}")
    if len(issues) > MAX_SHOWN:
        print(f"    ... and {len(issues) - MAX_SHOWN} more "
              f"(python3 bin/audit-encounter-crs.py --full)")


def main():
    if not os.path.exists(TOOL):
        print(f"FAIL: {TOOL} is missing - the encounter-cache gate cannot run "
              f"without the tool it shares its scan with")
        return 1

    cr_issues, diff_issues = load_tool().scan()
    if not cr_issues and not diff_issues:
        print("OK: encounter CR and Difficulty caches are in sync")
        return 0

    print("FAIL: encounter caches have drifted from their sources")
    if cr_issues:
        print(f"\n  {len(cr_issues)} cached CR values disagree with the "
              f"creature blueprint:")
        show(cr_issues, lambda i: (f"{i['resref']:<20} cached {i['cached']:g} "
                                   f"!= blueprint {i['actual']:g}   "
                                   f"{i['encounter']} in {i['where']}"))
    if diff_issues:
        print(f"\n  {len(diff_issues)} Difficulty values disagree with "
              f"DifficultyIndex:")
        show(diff_issues, lambda i: (f"{i['encounter']:<20} index {i['index']} "
                                     f"=> Difficulty {i['actual']}, found "
                                     f"{i['cached']}   in {i['where']}"))
    print(f"\n  Fix: {FIX}")
    return 1


if __name__ == "__main__":
    sys.exit(main())
