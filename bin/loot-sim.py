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
    python3 bin/loot-sim.py --gems                # sockets and gems (Phase 5): sockets by rarity,
                                                  #   gems per chest open / per kill, gem tier mix
                                                  #   by level, and the merge table (what each gem
                                                  #   does to each existing value)
    python3 bin/loot-sim.py --reforge 40,3        # Shard of Fate (Phase 7): boss Shard drops, and
                                                  #   N reforges of a level-40 Epic item - value vs
                                                  #   budget, set changed, bounds never broken
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


def gems(data, levels, n, seed):
    """Phase 5: sockets on rolled items, socket gems from chests and kills, and
    what each gem does to each value it can meet (loot_model.gem_merge)."""
    tiers = data["rarity"]["tiers"]
    T = len(tiers)
    print("== sockets on rolled items (rarity.json sockets; existing gear: loot/sockets.json)")
    for i, t in enumerate(tiers):
        lo, hi = t.get("sockets", [0, 0])
        print("   %-10s %d-%d  (mean %.1f)" % (t["name"], lo, hi, (lo + hi) / 2.0))
    exc = lm.socket_exceptions(data)
    print("   existing module items listed off the default: %d (%s)" % (
        len(exc), ", ".join("%d socket(s): %d" % (k, v) for k, v in
                            sorted(collections.Counter(exc.values()).items()))))
    rng = random.Random(seed)
    print("== socket gems per source (%d trials per level)" % n)
    print("   %-14s %s" % ("source", "  ".join("lvl %-2d gems  tier mix C/U/R/E/L %%" % l for l in levels)))
    srcs = [("chest " + p, p, None) for p, v in data["sources"]["profiles"].items()
            if lm.prof_get(v, "socket_gem_chance")]
    srcs += [("kill " + c, None, c) for c in lm.CREATURE_CLASSES]
    for label, prof, cls in srcs:
        cells = []
        for lvl in levels:
            got = collections.Counter()
            k = 0
            for _ in range(n):
                if prof:
                    gs = lm.chest_contents(data, lvl, prof, rng)["socket_gems"]
                else:
                    gs = [x["gem"] for x in lm.creature_drop(data, cls, 0, lvl, rng) if "gem" in x]
                for _f, tier in gs:
                    got[tier] += 1
                    k += 1
            mix = "/".join("%.0f" % (100.0 * got[i] / max(1, k)) for i in range(T))
            cells.append("%5.3f  %-18s" % (k / n, mix))
        print("   %-14s %s" % (label, "  ".join("      " + c for c in cells)))
    print("== merge table: existing value -> after one gem of each tier (C/U/R/E/L)")
    dmgpow = lm.damage_power()
    rows = {16: [None, 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15, 16]}
    lab = {1: "+1", 2: "+2", 3: "+3", 4: "+4", 5: "+5", 6: "1d4", 7: "1d6", 8: "1d8", 9: "1d10",
           10: "2d6", 11: "2d8", 12: "2d4", 13: "2d10", 14: "1d12", 15: "2d12", 16: "+6"}
    ab = lm.affix_by_id(data)
    for fam in lm.gem_families(data):
        a = ab[fam["affixes"][0]]
        cat = next(c for c in lm.CATEGORIES if lm.gem_fits(data, fam, c))
        key = (a["type"], a.get("sub") or 0)
        vals = rows.get(a["type"], [None] + list(range(1, max(fam["ladder"]) + 3)))
        name = (lambda r: lab.get(r, str(r))) if a["type"] == 16 else (lambda r: "+%d" % r)
        if fam["id"] not in ("fire", "hit", "ac", "str", "saves"):
            continue            # the other damage / ability families share these ladders
        print("   %s (%s; %s):" % (fam["stone"], fam["effect"], "/".join(map(str, fam["steps"]))))
        for v in vals:
            props = {} if v is None else {key: v}
            out = []
            for tier in range(T):
                r = lm.gem_merge(data, fam, tier, props, cat, dmgpow)
                out.append(name(r[3]) if isinstance(r, tuple) else "-")
            print("      %-6s -> %s" % ("none" if v is None else name(v), "  ".join("%-5s" % x for x in out)))


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
    acr = {a: e.get("area_cr") for a, e in data["area_levels"]["areas"].items()}

    def acr_s(a):
        v = acr.get(a)
        return "-" if v is None else "%g" % v
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

    champ = lm.area_champion_chances(data)
    champ_base = lm.champions_cfg(data)["chance"]

    def expected(r):
        """Expected drops from one kill of slot r, a normal creature's chance
        of spawning as a champion (elite drop chance) included."""
        if r["cls"] != "normal":
            return per_kill(r["cls"], r["cr"]) if r["cls"] else 0.0
        p = champ.get(r["area"], champ_base) / 1000.0
        return (1 - p) * per_kill("normal", r["cr"]) + p * per_kill("elite", r["cr"])

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
    pct = lm.area_percentile(data)
    w("**Levels are loot levels (1-60), not CRs.** A CR maps to a loot level through")
    w("`loot/levels.json` `cr_points`: %s. An area's loot level is the %dth-percentile CR of"
      % (", ".join("CR %d = %d" % (c, lm.level_for_cr(levels, c)) for c in (10, 25, 55, 100, 250, 500, 1000)), pct))
    w("its hostile creatures (`area_percentile`), shown as *area CR*, unless")
    w("`sources.json` `area_overrides` pins it.")
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
                                      sum(expected(r) for r in rs)))
    nrm = [r for r in rows if r["cls"] == "normal"]
    w("| ... of which champions (expected per clear) | %.0f | | |" % sum(
        champ.get(r["area"], champ_base) / 1000.0 for r in nrm))
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
    w("| area | area CR | area lvl | creature | resref | CR | loot lvl | over | slots | why |")
    w("|---|---|---|---|---|---|---|---|---|---|")
    grp = collections.OrderedDict()
    for r in sorted((r for r in rows if r["cls"] == "elite"),
                    key=lambda r: (aname(r["area"]).lower(), r["area"], -r["cr"], r["resref"])):
        k = (r["area"], r["resref"], r["cr"])
        if k not in grp:
            grp[k] = dict(r, n=0)
        grp[k]["n"] += 1
    for (a, rr, cr), r in grp.items():
        why = "elite_include" if rr in cc.get("elite_include", {}) else "auto"
        w("| %s (`%s`) | %s | %d | %s | `%s` | %g | %d | %+d | %d | %s |" % (
            aname(a), a, acr_s(a), r["alvl"], cname(rr), rr, cr, r["lvl"], r["lvl"] - r["alvl"], r["n"], why))
    if not grp:
        w("| - | | | | | | | | | |")
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

    ch = lm.champions_cfg(data)
    w("## Champions")
    w("")
    w("A normal creature may spawn as a champion: '%s' name prefix, a glow, +%d%% hit points, "
      "+%d attack, +%d damage, +%d AC, +%d saves, and the elite drop chance. Its CR rises by what "
      "the toolset formula's hit-point term pays for the extra HP (so XP and drop level follow). "
      "Kills count under the base creature in the bestiary, with a separate champion tally."
      % (ch["name_prefix"], ch["hp_pct"], ch["ab"], ch["damage"], ch["ac"], ch["saves"]))
    w("")
    w("Chance per spawn: %.1f%% in an area with no natural elites, falling linearly with the area's "
      "natural elite share to %.1f%% at %.0f%% elites, never lower." % (
          ch["chance"] / 10.0, ch["min_chance"] / 10.0, ch["density_cap"] / 10.0))
    w("")
    w("| champion chance | areas |")
    w("|---|---|")
    for pm, n in sorted(collections.Counter(champ.values()).items(), reverse=True):
        w("| %.1f%% | %d |" % (pm / 10.0, n))
    w("")
    w("Areas below the base chance:")
    w("")
    w("| area | natural elites / slots | champion chance |")
    w("|---|---|---|")
    for a in sorted((a for a, pm in champ.items() if pm != champ_base),
                    key=lambda a: (champ[a], aname(a).lower())):
        rs = [r for r in rows if r["area"] == a and r["cls"] in ("normal", "elite")]
        w("| %s (`%s`) | %d / %d | %.1f%% |" % (aname(a), a, sum(r["cls"] == "elite" for r in rs),
                                               len(rs), champ[a] / 10.0))
    w("")

    w("## Drops per area")
    w("")
    w("Areas with hostile creatures, by drops per clear (highest first, champions included).")
    w("")
    w("| area | area CR | lvl | slots | elite | boss | drops per clear | chest gear per fill |")
    w("|---|---|---|---|---|---|---|---|")
    chest = _chest_gear_by_area(data)
    by_area = collections.defaultdict(list)
    for r in rows:
        by_area[r["area"]].append(r)
    table = []
    for a, rs in by_area.items():
        drops = sum(expected(r) for r in rs)
        table.append((-round(drops, 6), aname(a).lower(), a, rs, drops))
    for _, _, a, rs, drops in sorted(table):
        w("| %s (`%s`) | %s | %d | %d | %d | %d | %.2f | %.2f |" % (
            aname(a), a, acr_s(a), alv.get(a, 0), len(rs), sum(1 for r in rs if r["cls"] == "elite"),
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


def wishlist_report(data, wish_bases, feats, caster, auto, n, seed):
    """Phase 6: share of each candidate base with and without the wishlist, per
    profile.  Mirrors Loot_WishPick through loot_model.roll(wish=...)."""
    cands = lm.wish_candidates(data, wish_bases, feats, caster, auto)
    names = {b["base"]: b["name"] for c in lm.CATEGORIES for b in data["bases"]["categories"][c]}
    if wish_bases:
        src = "wishlist"
    elif not auto:
        src = "Auto off"
    else:
        src = "Auto (%s)" % ("focus feats" if feats and any(
            set(data["costs"]["baseitems"][str(b)].get("focus_feats", [])) & set(feats)
            for b, _ in cands) else "proficiency")
    print("candidates (%s, chance %d/1000): %s" % (
        src, lm.wishlist_cfg(data)["chance"],
        ", ".join("%s x%d" % (names.get(b, b), w) for b, w in cands) or "none - plain random"))
    rows = {b for b, _ in cands}
    print("%-13s %10s %10s" % ("profile", "without", "with"))
    for prof in data["sources"]["profiles"]:
        res = []
        for wish in (None, cands):
            rng = random.Random(seed)
            hit = tot = 0
            for _ in range(n):
                r = lm.roll(data, 40, data["sources"]["profiles"][prof].get("rarity_floor", 0),
                            prof, rng=rng, wish=wish)
                if r.get("named"):
                    continue
                tot += 1
                hit += r["base"] in rows
            res.append(100.0 * hit / max(tot, 1))
        print("%-13s %9.1f%% %9.1f%%" % (prof, res[0], res[1]))


def reforge_report(data, spec, n, seed):
    """Phase 7: the Shard of Fate.  Boss Shard drops per kill, then N reforges
    of one rolled item (loot_model.reforge, the mirror of Loot_Reforge): the
    affix count, value against the budget, how often the affix set changes,
    and that a kept (forged) property's type is never re-rolled onto it."""
    rng = random.Random(seed)
    model = lm.CostModel(data["costs"])
    fate = lm.tokens_cfg(data)
    kills = 20000
    got = sum(1 for _ in range(kills)
              for x in lm.creature_drop(data, "boss", 0, 50, rng, model) if x.get("shard"))
    print("== Shard of Fate (loot/tokens.json fate)")
    print("   boss drop chance %d/1000 -> %.3f Shards per boss kill (%d simulated kills)"
          % (fate.get("boss_chance", 0), got / kills, kills))
    print("   bonus roll: %ds prompt, %dh lockout per boss, profile '%s'"
          % (fate.get("bonus_timeout_s", 0), fate.get("lockout_s", 0) // 3600,
             fate.get("bonus_profile")))
    parts = [int(x) for x in (spec or "40,3").split(",") if x.strip()]
    lvl = parts[0] if parts else 40
    rar = parts[1] if len(parts) > 1 else 3
    item = None
    for _ in range(500):
        r = lm.roll(data, lvl, rar, "lab", rng, model)
        if r.get("named") is None and r["rarity"] == rar and r["affixes"] \
                and (len(parts) < 3 or r["base"] == parts[2]):
            item = r
            break
    if item is None:
        print("   no rolled item matched level %d rarity %d%s"
              % (lvl, rar, "" if len(parts) < 3 else " base %d" % parts[2]))
        return
    ab = lm.affix_by_id(data)
    tiers = data["rarity"]["tiers"]
    print("== reforging: %s [%s, level %d, base %d] value %d / budget %d"
          % (item["name"], tiers[rar]["name"], lvl, item["base"], item["value"], item["budget"]))
    print("   affixes now: %s" % ", ".join("%s@%d" % a for a in item["affixes"]))
    # As the forge would see it: one forged Enhancement (+5) kept, and the
    # whole item capped at its value now plus 25%.
    kept = [(6, 0, 5)]
    cap = int(model.item_value(item["base"], kept + [
        (ab[i]["type"], ab[i].get("sub") or 0, c) for i, c in item["affixes"]]) * 1.25)
    for label, kp, vcap in (("plain reforge", [], None),
                            ("forged Enhancement +5 kept, whole item <= +25%%", kept, cap)):
        cnt = collections.Counter()
        vals, changed, over, dup, none = [], 0, 0, 0, 0
        old = frozenset(a for a, _ in item["affixes"])
        for _ in range(n):
            f = lm.reforge(data, item["base"], lvl, rar, kp, rng, model, value_cap=vcap,
                           prop_cap=6)
            if f is None:
                none += 1
                continue
            vals.append(f["value"])
            ids = frozenset(a for a, _ in f["affixes"])
            changed += ids != old
            over += f["value"] > f["budget"] or (vcap is not None and f["total"] > vcap)
            dup += any((ab[a]["type"], ab[a].get("sub") or 0) in {(t, s) for t, s, _c in kp}
                       for a in ids)
            cnt[len(f["affixes"])] += 1
        vals.sort()
        q = lambda p: vals[min(len(vals) - 1, int(p * len(vals)))] if vals else 0
        print("   %s (%d reforges):" % (label % () if "%%" in label else label, n))
        print("      affix count %s; value p50 %d p90 %d (budget %d); set changed %.0f%%;"
              % (dict(sorted(cnt.items())), q(0.5), q(0.9), item["budget"],
                 100.0 * changed / max(1, n - none)))
        print("      over a bound: %d; duplicated a kept type: %d; nothing fitted (Shard kept): %d"
              % (over, dup, none))


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
    ap.add_argument("--gems", action="store_true")
    ap.add_argument("--reforge", nargs="?", const="", default=None, metavar="LVL,RARITY[,BASE]",
                    help="Phase 7: Shard of Fate boss drops, and N reforges of one rolled "
                         "item (default 40,3 = level 40, Epic)")
    ap.add_argument("--wishlist", default=None, metavar="BASE[,BASE...]",
                    help="Phase 6: share of these base rows per profile with/without the wishlist")
    ap.add_argument("--auto-feats", default=None, metavar="FEAT[,FEAT...]",
                    help="Phase 6: with an empty --wishlist, the Auto list for these feat rows")
    ap.add_argument("--caster", action="store_true",
                    help="with --auto-feats: the character is a caster (magic staves in tier 2)")
    ap.add_argument("--auto-off", action="store_true", help="with --auto-feats: Auto switched off")
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
    if a.reforge is not None:
        reforge_report(data, a.reforge, min(a.n, 5000), a.seed)
        return 0
    if a.gems:
        gems(data, [int(x) for x in a.levels.split(",")], min(a.n, 5000), a.seed)
        return 0
    if a.wishlist is not None or a.auto_feats is not None:
        ints = lambda t: [int(x) for x in (t or "").split(",") if x.strip()]
        wishlist_report(data, ints(a.wishlist), ints(a.auto_feats), a.caster,
                        not a.auto_off, min(a.n, 5000), a.seed)
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
