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
    python3 bin/loot-sim.py --chests              # container fills (Phase 3): gear, gold,
                                                  #   gems and consumables per open, per
                                                  #   profile, plus chests by area level
    python3 bin/loot-sim.py --creatures           # creature drops (Phase 4): which creatures
                                                  #   are elite, margin sweep, drops per clear
    python3 bin/loot-sim.py --creatures --margin 7   # ...as if elite_margin were 7
    python3 bin/loot-sim.py --creatures --write   # regenerate CLAUDE-loot-creature-audit.md
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

AUDIT = lm.ROOT / "CLAUDE-loot-creature-audit.md"


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


def chests(data, levels, n, seed):
    """Phase 3: what one fill of each container profile holds."""
    model = lm.CostModel(data["costs"])
    tiers = data["rarity"]["tiers"]
    fam = {c["resref"]: c.get("family", "?") for c in data["consumables"]["items"]}
    profiles = [p for p, v in data["sources"]["profiles"].items()
                if p.startswith("chest") or v.get("gold_pct")]
    for prof in profiles:
        print("== container profile %s  (%d fills per level)" % (prof, n))
        print("   %-5s %6s %-34s %8s %8s %7s %6s  %s" % ("level", "gear", "rarity mix C/U/R/E/L %",
                                                     "gold p50", "gold p90", "as gems", "cons", "consumable families"))
        for lvl in levels:
            rng = random.Random(seed + lvl)
            gear = 0
            rar = collections.Counter()
            gold = []
            gems = 0
            cons = 0
            fams = collections.Counter()
            for _ in range(n):
                c = lm.chest_contents(data, lvl, prof, rng, model)
                gear += len(c["gear"])
                for g in c["gear"]:
                    rar[g["rarity"]] += 1
                gold.append(c["gold"] + sum(v for _, v in c["gems"]))
                gems += bool(c["gems"])
                cons += len(c["consumables"])
                for rr, _ in c["consumables"]:
                    fams[fam.get(rr, "?")] += 1
            mix = "/".join("%.1f" % (100.0 * rar[i] / max(1, gear)) for i in range(len(tiers)))
            print("   %-5d %6.2f %-34s %8s %8s %6.0f%% %6.2f  %s" % (
                lvl, gear / n, mix, fmt(pct(gold, 50)), fmt(pct(gold, 90)), 100.0 * gems / n,
                cons / n, ", ".join("%s %d%%" % (f, 100 * k / max(1, cons)) for f, k in fams.most_common(4))))
    areas = data["area_levels"]["areas"]
    band = collections.Counter()
    for a, e in areas.items():
        if e["chests"]:
            band[((e["level"] or 0) - 1) // 10 if e["level"] else -1] += e["chests"]
    print("== treasure containers by area loot level (loot/area_levels.json)")
    for b in sorted(band):
        print("   %s  %d" % ("no level" if b < 0 else "%2d-%2d" % (b * 10 + 1, b * 10 + 10), band[b]))


def _chest_gear_by_area(data):
    """{area: expected rolled gear items per fill of all its loot containers}."""
    scripts = {k.lower(): v["profile"] for k, v in data["sources"].get("scripts", {}).items()}
    profiles = data["sources"]["profiles"]
    out = collections.Counter()
    for area, d in lm.load_gits():
        for pl in lm.gff(d, "Placeable List", []) or []:
            for ev in lm.TREASURE_EVENTS:
                prof = scripts.get(str(lm.gff(pl, ev, "") or "").lower())
                if prof:
                    pr = profiles[prof]
                    out[area] += lm.prof_get(pr, "rolls") * lm.prof_get(pr, "gear_chance") / 1000.0
                    break
    return out


def creature_report(data, margin=None):
    """Phase 4 creature-drop audit as Markdown (deterministic: no dates, no RNG).

    The same text is CLAUDE-loot-creature-audit.md (--write); the loot gate
    notes when that file is stale."""
    import copy
    import boss_index as bi

    if margin is not None:
        data = copy.deepcopy(data)
        data["sources"]["creatures"]["elite_margin"] = margin
    cc = lm.creatures_cfg(data)
    m = cc["elite_margin"]
    classes = cc["classes"]
    levels = data["levels"]
    alv = {a: (e.get("level") or 0) for a, e in data["area_levels"]["areas"].items()}
    bosses = lm.boss_resrefs()
    slots = lm.creature_slots(also=frozenset(bosses))

    names = {}

    def cname(rr):
        if rr not in names:
            b = bi.load_blueprint(rr)
            names[rr] = (b["name"] if b else "(missing blueprint)").replace("|", "/")
        return names[rr]

    def aname(a):
        return (bi.area_name(a) or a).replace("|", "/")

    def per_kill(cls, cr):
        c = classes[cls]
        n = lm.creature_rolls(data, cls, cr) + c.get("named_chance", 0) / 1000.0
        return c["chance"] / 1000.0 * n

    rows = []
    for sl in slots:
        rr = sl["resref"]
        is_boss = rr in bosses
        cls = lm.creature_class(data, rr, sl["cr"], alv.get(sl["area"], 0), is_boss)
        lvl = lm.creature_level(data, rr, sl["cr"], is_boss, bosses)
        rows.append(dict(sl, cls=cls, lvl=lvl, alvl=alv.get(sl["area"], 0)))

    L = []
    w = L.append
    w("# Creature drops - elite audit (Loot Overhaul Phase 4)")
    w("")
    w("**Generated** by `python3 bin/loot-sim.py --creatures --write` from `loot/sources.json`")
    w("(`creatures`), `loot/levels.json`, `loot/area_levels.json` and the placed creatures in")
    w("`unpacked/*.git.json`. Do not hand-edit; re-run after a change. Roadmap: `lo-creature-drops`.")
    w("")
    w("A PC-credited kill of a hostile creature may leave rolled items on its corpse. Its class")
    w("decides how often:")
    w("")
    w("| class | rule | drop chance | rolls | rarity floor |")
    w("|---|---|---|---|---|")
    tiers = data["rarity"]["tiers"]
    for cls, rule in (("normal", "everything else"),
                      ("elite", "CR loot level >= area loot level + **%d** (`elite_margin`), or `elite_include`" % m),
                      ("boss", "in the Roll of the Fallen registry (`brd_db.nss`)")):
        c = classes[cls]
        pr = data["sources"]["profiles"][c["profile"]]
        rolls = str(lm.prof_get(pr, "rolls"))
        if cls == "boss" and c.get("extra_roll_cr"):
            rolls += " (+1 at CR %d+)" % c["extra_roll_cr"]
        if c.get("named_chance"):
            rolls += ", + named roll %.0f%%" % (c["named_chance"] / 10.0)
        w("| %s | %s | %.1f%% | %s | %s |" % (cls, rule, c["chance"] / 10.0, rolls,
                                            tiers[lm.prof_get(pr, "rarity_floor")]["name"]))
    w("")
    w("**To tune:** change `elite_margin`, or list a creature resref with a reason in")
    w("`elite_include` (always elite), `elite_exclude` (never elite) or `exclude` (never drops), then")
    w("`python3 bin/gen-loot-tables.py --apply` and re-run this report. `--margin N` previews another")
    w("margin without editing anything.")
    w("")
    w("Normal and elite creatures must be in a hostile faction (reputation toward PCs <= 10, the")
    w("area-level rule); registered bosses drop whatever faction they were placed in.")
    w("")
    w("Counting: a *slot* is one placed hostile creature, or one entry in a placed hostile")
    w("encounter's creature list. An encounter spawns some of its list, possibly more than once, so")
    w("encounter numbers are indicative. *Drops per clear* = expected rolled items from killing every")
    w("slot once. *Chest gear per fill* = expected rolled items from opening every loot container")
    w("in the area once.")
    w("")

    w("## Margin sweep")
    w("")
    w("| elite_margin | elite slots | % of non-boss | distinct creatures | areas |")
    w("|---|---|---|---|---|")
    nonboss = [r for r in rows if r["cls"] != "boss" and r["cls"] is not None]
    for mm in sorted({3, 5, 7, 10, 15, m}):
        el = [r for r in nonboss
              if r["resref"] in cc.get("elite_include", {})
              or (r["resref"] not in cc.get("elite_exclude", {}) and r["alvl"]
                  and lm.level_for_cr(levels, r["cr"]) >= r["alvl"] + mm)]
        w("| %s%d%s | %d | %.1f%% | %d | %d |" % ("**" if mm == m else "", mm, "**" if mm == m else "",
                                                len(el), 100.0 * len(el) / max(1, len(nonboss)),
                                                len({r["resref"] for r in el}), len({r["area"] for r in el})))
    w("")

    w("## Totals at margin %d" % m)
    w("")
    w("| class | slots | distinct creatures | drops per full clear |")
    w("|---|---|---|---|")
    for cls in lm.CREATURE_CLASSES:
        rs = [r for r in rows if r["cls"] == cls]
        w("| %s | %d | %d | %.1f |" % (cls, len(rs), len({r["resref"] for r in rs}),
                                      sum(per_kill(cls, r["cr"]) for r in rs)))
    ex = [r for r in rows if r["cls"] is None]
    w("| excluded | %d | %d | 0 |" % (len(ex), len({r["resref"] for r in ex})))
    w("")
    w("Rarity mix of one roll: " + "; ".join(
        "%s: %s" % (cls, " / ".join("%s %.1f%%" % (t["name"], 100 * p) for t, p in zip(
            tiers, lm.rarity_dist(data, lm.prof_get(data["sources"]["profiles"][classes[cls]["profile"]],
                                                    "rarity_floor")))
            if p > 0.0005))
        for cls in ("normal", "boss")) + " (elite rolls like normal).")
    w("")

    w("## Elite creatures at margin %d" % m)
    w("")
    w("Grouped by area. *over* = how far the creature's loot level is above the area's.")
    w("")
    w("| area | area lvl | creature | resref | CR | loot lvl | over | slots | why |")
    w("|---|---|---|---|---|---|---|---|---|")
    grp = collections.OrderedDict()
    for r in sorted((r for r in rows if r["cls"] == "elite"),
                    key=lambda r: (aname(r["area"]).lower(), r["area"], -r["cr"], r["resref"])):
        k = (r["area"], r["resref"], r["cr"])
        if k not in grp:
            grp[k] = dict(r, n=0)
        grp[k]["n"] += 1
    for (a, rr, cr), r in grp.items():
        why = "elite_include" if rr in cc.get("elite_include", {}) else "auto"
        w("| %s (`%s`) | %d | %s | `%s` | %g | %d | %+d | %d | %s |" % (
            aname(a), a, r["alvl"], cname(rr), rr, cr, r["lvl"], r["lvl"] - r["alvl"], r["n"], why))
    if not grp:
        w("| - | | | | | | | | |")
    w("")

    sup = [r for r in rows if r["resref"] in cc.get("elite_exclude", {})]
    if sup:
        w("## Kept normal by elite_exclude")
        w("")
        w("| creature | resref | slots | reason |")
        w("|---|---|---|---|")
        for rr in sorted({r["resref"] for r in sup}):
            w("| %s | `%s` | %d | %s |" % (cname(rr), rr, sum(1 for r in sup if r["resref"] == rr),
                                         cc["elite_exclude"][rr]))
        w("")
    if ex:
        w("## Never drop (exclude)")
        w("")
        w("| creature | resref | slots | reason |")
        w("|---|---|---|---|")
        for rr in sorted({r["resref"] for r in ex}):
            w("| %s | `%s` | %d | %s |" % (cname(rr), rr, sum(1 for r in ex if r["resref"] == rr),
                                         cc["exclude"][rr]))
        w("")

    w("## Drops per area")
    w("")
    w("Areas with hostile creatures, by drops per clear (highest first).")
    w("")
    w("| area | lvl | slots | elite | boss | drops per clear | chest gear per fill |")
    w("|---|---|---|---|---|---|---|")
    chest = _chest_gear_by_area(data)
    by_area = collections.defaultdict(list)
    for r in rows:
        by_area[r["area"]].append(r)
    table = []
    for a, rs in by_area.items():
        drops = sum(per_kill(r["cls"], r["cr"]) for r in rs if r["cls"])
        table.append((-round(drops, 6), aname(a).lower(), a, rs, drops))
    for _, _, a, rs, drops in sorted(table):
        w("| %s (`%s`) | %d | %d | %d | %d | %.2f | %.2f |" % (
            aname(a), a, alv.get(a, 0), len(rs), sum(1 for r in rs if r["cls"] == "elite"),
            sum(1 for r in rs if r["cls"] == "boss"), drops, chest.get(a, 0.0)))
    w("")
    return "\n".join(L)


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
    ap.add_argument("--chests", action="store_true")
    ap.add_argument("--creatures", action="store_true")
    ap.add_argument("--margin", type=int, default=None,
                    help="with --creatures: preview another elite_margin")
    ap.add_argument("--write", action="store_true",
                    help="with --creatures: write CLAUDE-loot-creature-audit.md")
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
    if a.chests:
        chests(data, [int(x) for x in a.levels.split(",")], min(a.n, 5000), a.seed)
        return 0
    if a.creatures:
        if a.write and a.margin is not None:
            sys.exit("--write records the committed elite_margin; drop --margin "
                     "(edit loot/sources.json to change it)")
        text = creature_report(data, a.margin)
        if a.write:
            AUDIT.write_text(text + "\n", encoding="utf-8")
            print("wrote %s" % AUDIT.relative_to(lm.ROOT))
        else:
            print(text)
        return 0
    bad = 0
    for lvl in (int(x) for x in a.levels.split(",")):
        bad += simulate(data, lvl, a.n, a.profile, a.floor, a.seed + lvl)
    return 1 if bad else 0


if __name__ == "__main__":
    sys.exit(main())
