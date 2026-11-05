#!/usr/bin/env python3
"""loot-sim.py - Monte Carlo over loot/*.json (Season 3 rolled loot).

The balance check to run before any build that touches loot data.  It rolls
items with bin/loot_model.py's ``roll()`` - the Python mirror of
``Loot_Roll()`` in unpacked/loot_inc.nss - and prints, per loot level:

  * the rarity mix (after floor + upgrades), the named-pool share and the
    unidentified share;
  * value p50 / p90 / max per rarity against that rarity's budget, and how many
    rolls sit above each forge's cap (such an item cannot be worked further, the
    same as the module's existing top gear);
  * how many affixes rolls carry, the downside rate, and the most common affixes.

Values come from the Python cost model (an estimate of GetGoldPieceValue; see
loot_model.py).  In game, Loot Lab's "dump" prints the engine's own value.

    python3 bin/loot-sim.py                       # 20000 rolls at levels 1,20,40,60
    python3 bin/loot-sim.py --levels 55,60 --n 50000 --profile boss
    python3 bin/loot-sim.py --floor 3             # force an Epic floor
    python3 bin/loot-sim.py --calibrate           # obtainable-gear value percentiles
    python3 bin/loot-sim.py --cr                  # CR -> loot level across the bestiary
"""

from __future__ import annotations

import argparse
import collections
import json
import random
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
import loot_model as lm  # noqa: E402


def pct(xs, p):
    if not xs:
        return 0
    xs = sorted(xs)
    return xs[min(len(xs) - 1, int(len(xs) * p / 100))]


def fmt(v):
    if v >= 1_000_000:
        return "%.2fM" % (v / 1e6)
    if v >= 1000:
        return "%.0fk" % (v / 1e3)
    return str(v)


def simulate(data, level, n, profile, floor, seed):
    rng = random.Random(seed)
    model = lm.CostModel(data["costs"])
    tiers = data["rarity"]["tiers"]
    by_rar = collections.defaultdict(list)
    named = unid = down = 0
    naff = collections.Counter()
    afx = collections.Counter()
    over = collections.Counter()
    over_budget = 0
    for _ in range(n):
        r = lm.roll(data, level, floor, profile, rng, model)
        if r["named"]:
            named += 1
            by_rar[r["rarity"]].append(None)
            continue
        by_rar[r["rarity"]].append(r["value"])
        unid += r["unidentified"]
        down += r["downside"]
        naff[len(r["affixes"])] += 1
        for a, _ in r["affixes"]:
            afx[a] += 1
        for cap, v in lm.FORGE_CAPS.items():
            if r["value"] > v:
                over[cap] += 1
        if r["value"] > r["budget"]:
            over_budget += 1
    print("== loot level %d  (profile %s, floor %s, %d rolls)" % (level, profile, tiers[floor]["name"], n))
    print("   %-10s %6s %9s %9s %9s %9s" % ("rarity", "share", "p50", "p90", "max", "budget"))
    for i, t in enumerate(tiers):
        vals = [v for v in by_rar.get(i, []) if v is not None]
        share = 100.0 * len(by_rar.get(i, [])) / n
        print("   %-10s %5.1f%% %9s %9s %9s %9s" % (
            t["name"], share, fmt(pct(vals, 50)), fmt(pct(vals, 90)),
            fmt(max(vals) if vals else 0), fmt(lm.rarity_budget(t, level))))
    print("   named %.2f%%  unidentified %.1f%%  downside %.1f%%  over budget %d"
          % (100.0 * named / n, 100.0 * unid / n, 100.0 * down / n, over_budget))
    print("   affix count: " + "  ".join("%d:%.1f%%" % (k, 100.0 * naff[k] / n) for k in sorted(naff)))
    print("   above forge cap: " + "  ".join("%s %.2f%%" % (k, 100.0 * over[k] / n) for k in lm.FORGE_CAPS))
    print("   top affixes: " + ", ".join("%s %.1f%%" % (a, 100.0 * c / n) for a, c in afx.most_common(10)))
    return over_budget


def calibrate():
    p = lm.ROOT / "module-index" / "item_index.json"
    if not p.exists():
        sys.exit("module-index/item_index.json missing - run the wiki once")
    d = json.loads(p.read_text())
    items = d["items"] if isinstance(d, dict) else d
    cat_of = {b["base"]: c for c, lst in lm.load_data()["bases"]["categories"].items() for b in lst}
    costs = lm.load_data()["costs"]["baseitems"]
    label_to_row = {v["label"]: int(k) for k, v in costs.items()}
    groups = collections.defaultdict(list)
    for it in items:
        if not it.get("accessible"):
            continue
        v = int(float(it.get("cost_gp") or 0))
        row = label_to_row.get(it.get("base_item"))
        groups["all"].append(v)
        groups[cat_of.get(row, "other")].append(v)
    print("obtainable-gear gold value by loot category (module-index/item_index.json):")
    print("   %-9s %5s %8s %8s %8s %8s %8s %8s" % ("category", "n", "p50", "p75", "p90", "p95", "p99", "max"))
    for k in ["all"] + list(lm.CATEGORIES) + ["other"]:
        xs = groups.get(k, [])
        if xs:
            print("   %-9s %5d %8s %8s %8s %8s %8s %8s" % (k, len(xs), *(fmt(pct(xs, q)) for q in (50, 75, 90, 95, 99)), fmt(max(xs))))


def cr_table():
    p = lm.ROOT / "module-index" / "creature_index.json"
    d = json.loads(p.read_text())
    items = d["creatures"] if isinstance(d, dict) and "creatures" in d else d
    if isinstance(items, dict):
        items = list(items.values())
    levels = lm.load_data()["levels"]
    hist = collections.Counter()
    for c in items:
        if c.get("faction_name") not in ("Hostile", "Evil") or not c.get("locations"):
            continue
        try:
            cr = float(c.get("cr") or 0)
        except ValueError:
            continue
        hist[(lm.level_for_cr(levels, cr) - 1) // 10] += 1
    print("placed Hostile/Evil creatures by loot level band:")
    for b in sorted(hist):
        print("   %2d-%2d  %d" % (b * 10 + 1, b * 10 + 10, hist[b]))


def main():
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--n", type=int, default=20000)
    ap.add_argument("--levels", default="1,20,40,60")
    ap.add_argument("--profile", default="lab")
    ap.add_argument("--floor", type=int, default=0)
    ap.add_argument("--seed", type=int, default=1)
    ap.add_argument("--calibrate", action="store_true")
    ap.add_argument("--cr", action="store_true")
    a = ap.parse_args()
    if a.calibrate:
        calibrate()
        return 0
    if a.cr:
        cr_table()
        return 0
    data = lm.load_data()
    errs = lm.validate(data)
    if errs:
        print("loot data is invalid - fix first:\n  - " + "\n  - ".join(errs))
        return 1
    bad = 0
    for lvl in (int(x) for x in a.levels.split(",")):
        bad += simulate(data, lvl, a.n, a.profile, a.floor, a.seed + lvl)
    return 1 if bad else 0


if __name__ == "__main__":
    sys.exit(main())
