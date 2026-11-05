#!/usr/bin/env python3
"""gen-area-loot-levels.py - every area's loot level -> loot/area_levels.json.

Loot Overhaul Phase 3 (roadmap rng-based-gear-diablo-world-of-warcraft-style).
A chest rolls at its AREA's loot level, not the opener's, so a level-60 player
gets nothing special out of a level-5 dungeon's chests.  The level is the
median CR of the area's hostile creatures (placed instances and placed
encounter pools; "hostile" = reputation toward players <= 10 in
repute.fac.json) run through loot/levels.json, unless loot/sources.json
``area_overrides`` pins it.

An area that holds a treasure container but has no hostile creatures - a town,
an inn - has nothing to take a median of.  The build gate fails until such an
area has an override; ``--suggest`` proposes one from the nearest areas that
do have a level (module-index/area_graph.json, which the wiki build writes).

The scan lives in bin/loot_model.py (area_scan / area_levels_doc), so this
tool, gen-loot-tables.py and tests/check_loot_tables.py can never disagree.

    python3 bin/gen-area-loot-levels.py            # dry run: say if stale, list gaps
    python3 bin/gen-area-loot-levels.py --apply    # write loot/area_levels.json
    python3 bin/gen-area-loot-levels.py --suggest  # override proposals for the gaps
    python3 bin/gen-area-loot-levels.py --table    # every area with chests, by level

After --apply: python3 bin/gen-loot-tables.py --apply (the levels are compiled
into loot_data_inc.nss), then a clean repack.
"""

from __future__ import annotations

import argparse
import collections
import json
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
import loot_model as lm  # noqa: E402

OUT = lm.LOOT_DIR / "area_levels.json"


def _names():
    out = {}
    for p in lm.UNPACKED.glob("*.are.json"):
        d = json.loads(p.read_text())
        n = lm.gff(d, "Name", {}) or {}
        out[p.name[:-len(".are.json")]] = str(n.get("0", "")) if isinstance(n, dict) else str(n)
    return out


def suggest(doc):
    p = lm.ROOT / "module-index" / "area_graph.json"
    if not p.exists():
        sys.exit("module-index/area_graph.json missing - run the wiki once")
    g = json.loads(p.read_text())["areas"]
    adj = collections.defaultdict(set)
    for a, n in g.items():
        for t in n.get("transitions", []):
            adj[a].add(t["to"])
            adj[t["to"]].add(a)
    areas = doc["areas"]
    names = _names()
    gaps = [a for a, e in areas.items() if e["chests"] and e["level"] is None]
    if not gaps:
        print("no gaps: every area with a treasure container has a level")
        return
    print("override proposals (median level of the nearest areas that have one):")
    for a in gaps:
        seen = {a}
        frontier = [a]
        found = []
        hops = 0
        while frontier and not found and hops < 6:
            hops += 1
            nxt = []
            for x in frontier:
                for y in sorted(adj[x]):
                    if y not in seen:
                        seen.add(y)
                        nxt.append(y)
            found = [(y, areas[y]["level"]) for y in nxt
                     if y in areas and areas[y]["level"] is not None]
            frontier = nxt
        lv = int(lm._median([v for _, v in found])) if found else 1
        print('  "%s": {"level": %d, "reason": "%s: no hostiles; median of %s"}  # %d chests, %d hop(s)'
              % (a, lv, names.get(a, a).replace('"', ""),
                 ", ".join("%s %d" % f for f in found) or "nothing reachable",
                 areas[a]["chests"], hops))


def table(doc):
    names = _names()
    rows = sorted(((e["level"] or 0, a, e) for a, e in doc["areas"].items() if e["chests"]))
    print("%-4s %-18s %-6s %-9s %-8s %s" % ("lvl", "area", "chests", "medianCR", "source", "name"))
    for lv, a, e in rows:
        print("%-4s %-18s %-6d %-9s %-8s %s" % (lv or "-", a, e["chests"],
                                              e["median_cr"] if e["median_cr"] is not None else "-",
                                              e["source"], names.get(a, "")))


def main():
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--apply", action="store_true")
    ap.add_argument("--suggest", action="store_true")
    ap.add_argument("--table", action="store_true")
    a = ap.parse_args()
    data = lm.load_data()
    doc = lm.area_levels_doc(data)
    if a.suggest:
        suggest(doc)
        return 0
    if a.table:
        table(doc)
        return 0
    gaps = [x for x, e in doc["areas"].items() if e["chests"] and e["level"] is None]
    if gaps:
        print("%d area(s) with treasure containers have no level - add area_overrides "
              "(--suggest): %s" % (len(gaps), ", ".join(gaps)))
    text = lm.dump_area_levels(doc)
    if OUT.exists() and OUT.read_text() == text:
        print("ok: %s is up to date" % OUT.relative_to(lm.ROOT))
        return 1 if gaps else 0
    if a.apply:
        OUT.write_text(text)
        n = sum(1 for e in doc["areas"].values() if e["level"] is not None)
        print("wrote %s (%d areas, %d with a level)" % (OUT.relative_to(lm.ROOT), len(doc["areas"]), n))
        return 1 if gaps else 0
    print("%s is stale - re-run with --apply" % OUT.relative_to(lm.ROOT))
    return 1


if __name__ == "__main__":
    sys.exit(main())
