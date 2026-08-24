#!/usr/bin/env python3
"""Resync the cached CR and Difficulty fields on encounters with their sources.

WHY THIS EXISTS
    Player report `encounter-spawns-levels-41-60`: at high level some encounters
    stop producing their strong creatures. In Mirkwood Central South the CR-45
    spiders never appear -- you get Giant Spiders (CR 21) and a Spider-Queen
    (CR 27). In Dimholt the Thing of the Dark never spawns.

    Encounters in this module are 100% stock engine behaviour: every encounter
    instance has empty OnEntered/OnExhausted/OnHeartbeat, there are no nw_e0_*
    overrides in unpacked/, and no scripted spawner touches them. The only
    inputs the engine has are the stored GFF fields -- and two of them lie.

    A. THE CACHED CR.  Every encounter creature-list entry carries its own `CR`,
       copied from the blueprint by the toolset when the creature was added to
       the list. Blueprints were rebalanced for levels 41-60 afterwards; the
       caches were not. The engine sorts the list high->low and adds creatures
       while CR <= the remaining budget, so a wrong cache misdirects the whole
       selection. `spidgiant001` is cached at CR 147 but is really CR 21, so the
       engine spends nearly the entire budget on what it believes is the
       toughest thing in the pool and is actually a trash mob -- which is
       exactly the Mirkwood report.

    B. THE DIFFICULTY VALUE.  encdifficulty.2da maps the five toolset settings
       to VeryEasy=0 Easy=1 Normal=2 Hard=5 Impossible=9. `DifficultyIndex` is
       the row, `Difficulty` is that row's VALUE. 44 of 81 blueprints and 472 of
       778 placed instances carry Difficulty 0 while DifficultyIndex says Hard
       or Impossible -- including both encounters in the report (`hardspiders`
       is index 4 / value 0, `dimwald` is index 3 / value 0). Whichever of the
       two the engine reads, they must not disagree.

WHY THIS ONE AUTO-FIXES AND bin/audit-loot-divergence.py DOES NOT
    Loot divergence is a judgement call -- only a human can say whether a
    placement or its blueprint is the intended truth. Here there is nothing to
    judge: both fields are caches, and their source is authoritative by
    definition. So this tool repairs rather than reports.

WHAT IT DELIBERATELY DOES NOT TOUCH
    Creature blueprint ChallengeRating. It is read live on every kill for XP
    (unpacked/sha_xpsystem.nss), gold (unpacked/gpondeath.nss, iGP = iCR*8+d20),
    the bestiary (unpacked/bst_ondeath.nss) and the boss board's CR > 60 rule
    (bin/gen-boss-registry.py). Only the encounter's *copy* of it moves, so the
    two agree afterwards and none of those consumers change.

    Entries whose resref has no .utc.json are skipped, not reported: 171
    encounter resrefs are stock base-game creatures (nw_*, x2_*, zep_*) that
    live in the game data rather than unpacked/, so there is no local blueprint
    to compare against.

USAGE
    python3 bin/audit-encounter-crs.py            # dry-run report
    python3 bin/audit-encounter-crs.py --full     # every row, not just a sample
    python3 bin/audit-encounter-crs.py --apply    # write the files

    tests/check_encounter_crs.py imports scan() from here, so the gate can never
    disagree with the fixer.
"""

import argparse
import importlib.util
import json
import os
import sys
from collections import defaultdict
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
UNPACKED = ROOT / "unpacked"

# encdifficulty.2da, VALUE column: the number the toolset caches into
# `Difficulty` for each `DifficultyIndex` row.
ENC_DIFFICULTY = {0: 0, 1: 1, 2: 2, 3: 5, 4: 9}

FIX = "python3 bin/audit-encounter-crs.py --apply"


def _boss_index():
    """Import bin/boss_index.py for the shared GFF helpers (hyphen-free name,
    but keep the loader symmetric with the rest of bin/)."""
    spec = importlib.util.spec_from_file_location(
        "boss_index", str(ROOT / "bin" / "boss_index.py"))
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


_bi = _boss_index()
gv = _bi.gv
load_blueprint = _bi.load_blueprint
area_name = _bi.area_name


def blueprint_cr(resref, cache={}):
    """Current ChallengeRating of a creature blueprint, or None when the resref
    is a stock base-game creature with no .utc.json in unpacked/."""
    if resref not in cache:
        bp = load_blueprint(resref, UNPACKED)
        cache[resref] = None if bp is None else bp["cr"]
    return cache[resref]


def _encounters(data, path):
    """Yield every encounter struct in a loaded .ute.json or .git.json."""
    if path.name.endswith(".ute.json"):
        yield data
    else:
        for enc in gv(data.get("Encounter List")) or []:
            yield enc


def _where(path):
    """Human label for a file: the area's display name, or the blueprint name."""
    if path.name.endswith(".ute.json"):
        return f"blueprint {path.name[:-len('.ute.json')]}"
    area = path.name[:-len(".git.json")]
    return f"{area_name(area, UNPACKED)} ({area})"


def scan(unpacked=UNPACKED):
    """Find every stale cache. Returns (cr_issues, diff_issues).

    cr_issues:   dicts with file/where/encounter/resref/cached/actual
    diff_issues: dicts with file/where/encounter/index/cached/actual
    Both are pure reads -- nothing is written here, so the build gate and the
    --apply path see exactly the same set.
    """
    cr_issues, diff_issues = [], []
    files = sorted(unpacked.glob("*.ute.json")) + sorted(unpacked.glob("*.git.json"))
    for path in files:
        data = json.loads(path.read_text(encoding="utf-8"))
        where = _where(path)
        for enc in _encounters(data, path):
            template = gv(enc.get("TemplateResRef")) or "?"

            index = gv(enc.get("DifficultyIndex"))
            want = ENC_DIFFICULTY.get(index)
            have = gv(enc.get("Difficulty"))
            if want is not None and have != want:
                diff_issues.append({
                    "file": path, "where": where, "encounter": template,
                    "index": index, "cached": have, "actual": want,
                })

            for slot in gv(enc.get("CreatureList")) or []:
                resref = gv(slot.get("ResRef"))
                actual = blueprint_cr(resref)
                if actual is None:
                    continue  # stock base-game creature, no local blueprint
                cached = gv(slot.get("CR"))
                if abs(float(cached) - actual) > 1e-6:
                    cr_issues.append({
                        "file": path, "where": where, "encounter": template,
                        "resref": resref, "cached": float(cached),
                        "actual": actual,
                    })
    return cr_issues, diff_issues


def apply(unpacked=UNPACKED):
    """Rewrite both caches from their sources. Returns (files, crs, diffs)."""
    cr_issues, diff_issues = scan(unpacked)
    touched = {i["file"] for i in cr_issues} | {i["file"] for i in diff_issues}
    for path in sorted(touched):
        data = json.loads(path.read_text(encoding="utf-8"))
        for enc in _encounters(data, path):
            want = ENC_DIFFICULTY.get(gv(enc.get("DifficultyIndex")))
            if want is not None:
                enc["Difficulty"]["value"] = want
            for slot in gv(enc.get("CreatureList")) or []:
                actual = blueprint_cr(gv(slot.get("ResRef")))
                if actual is not None:
                    slot["CR"]["value"] = float(actual)
        path.write_text(json.dumps(data, indent=2, ensure_ascii=False) + "\n",
                        encoding="utf-8")
    return len(touched), len(cr_issues), len(diff_issues)


def report(cr_issues, diff_issues, full=False):
    print("=" * 78)
    print("STALE CACHED CR  (encounter creature list vs creature blueprint)")
    print("=" * 78)
    if not cr_issues:
        print("  none -- every encounter entry matches its blueprint.")
    else:
        by_resref = defaultdict(list)
        for i in cr_issues:
            by_resref[(i["resref"], i["cached"], i["actual"])].append(i)
        print(f"  {len(cr_issues)} entries across "
              f"{len(by_resref)} creatures:\n")
        print(f"  {'resref':<20} {'cached':>9} {'blueprint':>10} {'entries':>8}"
              f"   worst drift")
        for (resref, cached, actual), rows in sorted(
                by_resref.items(), key=lambda kv: -abs(kv[0][1] - kv[0][2])):
            print(f"  {resref:<20} {cached:>9g} {actual:>10g} {len(rows):>8}"
                  f"   {abs(cached - actual):>+g}")
        print()
        for (resref, _, _), rows in sorted(by_resref.items()):
            shown = rows if full else rows[:3]
            for r in shown:
                print(f"    {resref:<20} {r['encounter']:<18} {r['where']}")
            if len(rows) > len(shown):
                print(f"    {'':<20} ... and {len(rows) - len(shown)} more "
                      f"(--full to list)")

    print()
    print("=" * 78)
    print("DIFFICULTY DESYNC  (Difficulty vs encdifficulty.2da[DifficultyIndex])")
    print("=" * 78)
    if not diff_issues:
        print("  none -- every encounter's Difficulty matches its index.")
    else:
        labels = {0: "VeryEasy", 1: "Easy", 2: "Normal", 3: "Hard",
                  4: "Impossible"}
        blueprints = [i for i in diff_issues if i["file"].name.endswith(".ute.json")]
        instances = [i for i in diff_issues if not i["file"].name.endswith(".ute.json")]
        print(f"  {len(blueprints)} blueprints, {len(instances)} placed "
              f"instances.\n")
        by_index = defaultdict(int)
        for i in diff_issues:
            by_index[i["index"]] += 1
        for index in sorted(by_index):
            print(f"    index {index} ({labels.get(index, '?'):<10}) should be "
                  f"Difficulty {ENC_DIFFICULTY[index]:<2} -- "
                  f"{by_index[index]} wrong")
        print()
        shown = diff_issues if full else diff_issues[:15]
        for i in shown:
            print(f"    {i['encounter']:<18} index {i['index']} "
                  f"Difficulty {i['cached']} -> {i['actual']:<2} {i['where']}")
        if len(diff_issues) > len(shown):
            print(f"    ... and {len(diff_issues) - len(shown)} more "
                  f"(--full to list)")


def main():
    ap = argparse.ArgumentParser(
        description="Resync encounter cached CR and Difficulty with their sources.")
    ap.add_argument("--apply", action="store_true",
                    help="write the files (default is a dry-run report)")
    ap.add_argument("--full", action="store_true",
                    help="list every row instead of a sample")
    args = ap.parse_args()

    if not UNPACKED.is_dir():
        print(f"FAIL: {UNPACKED} is missing", file=sys.stderr)
        return 2

    cr_issues, diff_issues = scan()
    report(cr_issues, diff_issues, full=args.full)

    total = len(cr_issues) + len(diff_issues)
    print()
    if not total:
        print("Nothing to do -- both caches are in sync.")
        return 0
    if args.apply:
        files, crs, diffs = apply()
        print(f"Wrote {files} files: {crs} CR values and {diffs} Difficulty "
              f"values resynced.")
        left_cr, left_diff = scan()
        if left_cr or left_diff:
            print(f"FAIL: {len(left_cr) + len(left_diff)} issues survived the "
                  f"rewrite", file=sys.stderr)
            return 1
        print("Re-scan clean.")
        return 0
    print(f"Dry run. Nothing written. Re-run with --apply. ({total} issues)")
    return 0


if __name__ == "__main__":
    sys.exit(main())
