#!/usr/bin/env python3
"""creature-cr-audit.py - where this module's stored creature CRs have drifted
from what the toolset would compute, and what a resync would change here.

The CR itself is computed by nwn_manager's ``bin/nwn-cr`` (the toolset formula,
bin/nwn_wiki/cr.py there); this script runs it and joins the result with what
only this module knows:

  * loot class (Loot Overhaul Phase 4) and area loot level, before and after;
  * the Roll of the Fallen boss board (gen-boss-registry.py's CR > 60
    single-instance rule) - a resync can add or drop bosses;
  * kill XP, which reads the stored CR live.

Writes CLAUDE-creature-cr-audit.md with --write (generated; never hand-edit).
Nothing in unpacked/ is changed - the resync itself is
``nwn-cr --project . --resync <list> --apply``.

    python3 bin/creature-cr-audit.py            # print the summary
    python3 bin/creature-cr-audit.py --write    # regenerate the audit file
"""

import argparse
import collections
import copy
import importlib.util
import json
import subprocess
import sys
import tempfile
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
sys.path.insert(0, str(ROOT / "bin"))
import boss_index as bi  # noqa: E402
import loot_model as lm  # noqa: E402

NWN_CR = ROOT.parent / "nwn_manager" / "bin" / "nwn-cr"
AUDIT = ROOT / "CLAUDE-creature-cr-audit.md"
DRIFT = 0.10                      # listed when stored is off by more than this
UTILITY = ("q_", "cbd_", "cp_", "dmfi_", "ds_")   # agent/tool-made NPCs, CR often hand-set


def run_nwn_cr():
    if not NWN_CR.exists():
        sys.exit(f"{NWN_CR} not found (the nwn_manager repo must sit beside this one)")
    with tempfile.TemporaryDirectory() as td:
        out = Path(td) / "cr.json"
        subprocess.run([sys.executable, str(NWN_CR), "--project", str(ROOT), "--json", str(out)],
                       check=True, capture_output=True, text=True)
        return {r["resref"]: r for r in json.loads(out.read_text())["creatures"]}


def boss_board(cr_override):
    """Registered resrefs under gen-boss-registry's rule, with CRs overridden."""
    spec = importlib.util.spec_from_file_location("gbr", ROOT / "bin" / "gen-boss-registry.py")
    g = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(g)
    orig = bi.load_blueprint

    def patched(rr, unpacked=bi.UNPACKED):
        b = orig(rr, unpacked)
        if b and rr in cr_override:
            b = dict(b, cr=cr_override[rr])
        return b
    g.bi.load_blueprint = patched
    try:
        placements, enc_slots = bi.build_placement_indices()
        inc, _exc = g.classify(placements, enc_slots)
        grouped, _al, _rep = g.group_aliases(inc)
        grouped, _col = g.drop_tag_area_collisions(grouped)
        return {r["resref"] for r in g.build_rows(grouped)}
    finally:
        g.bi.load_blueprint = orig


def classes_and_levels(data, cr_of):
    """(area levels, {(area, resref): class}) with blueprint CRs replaced by cr_of."""
    bosses = lm.boss_resrefs()
    slots = lm.creature_slots(also=frozenset(bosses))
    pct = lm.area_percentile(data)
    over = data["sources"].get("area_overrides", {})
    by_area = collections.defaultdict(list)
    for s in lm.creature_slots():
        by_area[s["area"]].append(cr_of(s["resref"], s["cr"]))
    levels = {}
    for a, crs in by_area.items():
        levels[a] = int(over[a]["level"]) if a in over else lm.level_for_cr(
            data["levels"], lm._percentile(crs, pct))
    for a, e in over.items():
        levels.setdefault(a, int(e["level"]))
    cls = {}
    for s in slots:
        c = lm.creature_class(data, s["resref"], cr_of(s["resref"], s["cr"]),
                              levels.get(s["area"], 0), s["resref"] in bosses)
        cls[(s["area"], s["resref"])] = c
    return levels, cls


def report(rows):
    data = lm.load_data()
    placements, enc_slots = bi.build_placement_indices()
    spawned = {rr for rr in rows if placements.get(rr) or enc_slots.get(rr)}

    def rel(r):
        return abs(r["calc"] - r["stored"]) / max(1.0, r["stored"])
    drift = {rr: r for rr, r in rows.items() if rel(r) > DRIFT and not r["unresolved_items"]}
    # The resync scenario leaves the utility NPCs out: their CRs are hand-set.
    resync_cr = {rr: r["calc"] for rr, r in drift.items() if not rr.startswith(UTILITY)}

    def now(rr, cr):
        return cr

    def after(rr, cr):
        # A placed instance keeps its own CR today; after a resync every slot of
        # a drifted blueprint carries the blueprint's computed CR (approximate
        # for an instance whose gear differs from its blueprint).
        return resync_cr.get(rr, cr)

    lv0, cls0 = classes_and_levels(data, now)
    lv1, cls1 = classes_and_levels(data, after)
    board0 = boss_board({})
    board1 = boss_board(resync_cr)

    names = {}

    def name(rr):
        if rr not in names:
            b = bi.load_blueprint(rr)
            names[rr] = (b["name"] if b else rr).replace("|", "/")
        return names[rr]

    L = []
    w = L.append
    w("# Creature CR drift audit")
    w("")
    w("**Generated** by `python3 bin/creature-cr-audit.py --write`, from nwn_manager's `bin/nwn-cr`")
    w("(the toolset's challenge-rating formula, calibrated in `bin/nwn_wiki/cr.py` there) joined with")
    w("this module's loot levels and boss rule. Do not hand-edit. Roadmap: `lo-creature-drops`.")
    w("")
    w("The toolset recomputes a creature's stored CR only when its Properties dialog is OK'd. Every")
    w("edit made outside it (scripts, the July +12-abilities pass, gear revalued by the forge rework)")
    w("leaves the stored CR stale. Stored CR drives kill XP, encounter spawn budgets, area loot")
    w("levels, the elite rule and the boss board.")
    w("")
    w("## How well the formula reproduces stored CRs")
    w("")
    ok = [r for r in rows.values() if not r["unresolved_items"]]
    w("| set | blueprints | exact | within 2% | within 10% | within 25% |")
    w("|---|---|---|---|---|---|")
    for label, rs in (("all with every item resolved", ok),
                      ("CRAdjust = 0", [r for r in ok if r["cr_adjust"] == 0]),
                      ("CRAdjust != 0", [r for r in ok if r["cr_adjust"] != 0])):
        e = [rel(r) for r in rs]
        n = max(1, len(rs))
        w("| %s | %d | %d (%.0f%%) | %d | %d (%.0f%%) | %d |" % (
            label, len(rs), sum(x == 0 for x in e), 100.0 * sum(x == 0 for x in e) / n,
            sum(x <= .02 for x in e), sum(x <= .10 for x in e), 100.0 * sum(x <= .10 for x in e) / n,
            sum(x <= .25 for x in e)))
    w("")
    w("%d blueprints have an item the formula cannot price (a hak-only item); they are left out." % (
        len(rows) - len(ok)))
    w("")

    groups = collections.OrderedDict((("utility", []), ("items", []), ("other", [])))
    for rr, r in sorted(drift.items()):
        if rr not in spawned:
            continue
        g = "utility" if rr.startswith(UTILITY) else ("items" if r["dominant"] == "items" else "other")
        groups[g].append(rr)
    w("## Summary of a full resync (every spawned non-utility blueprint off by more than %d%%)" % (DRIFT * 100))
    w("")
    w("| | count |")
    w("|---|---|")
    w("| drifted blueprints that spawn | %d |" % sum(len(v) for v in groups.values()))
    w("| ... utility NPCs (`%s`), CR probably hand-set on purpose | %d |" % (
        "`, `".join(UTILITY), len(groups["utility"])))
    w("| ... drift driven mostly by **item value** | %d |" % len(groups["items"]))
    w("| ... other | %d |" % len(groups["other"]))
    up = [rr for v in groups.values() for rr in v if drift[rr]["calc"] > drift[rr]["stored"]]
    w("| CR would rise / fall | %d / %d |" % (len(up), sum(len(v) for v in groups.values()) - len(up)))
    joins = sorted(board1 - board0)
    leaves = sorted(board0 - board1)
    w("| boss board: joins / leaves | %d / %d |" % (len(joins), len(leaves)))
    moved = sorted(a for a in set(lv0) | set(lv1) if lv0.get(a) != lv1.get(a))
    w("| area loot levels that change | %d |" % len(moved))
    flips = collections.Counter((cls0.get(k), cls1.get(k)) for k in cls0 if cls0.get(k) != cls1.get(k))
    w("| loot-class changes (slots) | %s |" % (", ".join(
        "%s->%s %d" % (a, b, n) for (a, b), n in sorted(flips.items(), key=lambda x: -x[1])) or "none"))
    w("")
    if joins or leaves:
        w("**Boss board changes:** joins %s; leaves %s." % (
            ", ".join("`%s` (%s)" % (r, name(r)) for r in joins) or "none",
            ", ".join("`%s` (%s)" % (r, name(r)) for r in leaves) or "none"))
        w("")

    titles = {"utility": "Utility NPCs (likely hand-set - probably leave alone)",
              "items": "Drift driven by item value",
              "other": "Other drift (stats, levels, HP changed since the last toolset save)"}
    for g, rrs in groups.items():
        w("## %s" % titles[g])
        w("")
        if not rrs:
            w("None.")
            w("")
            continue
        w("XP note: kill XP scales with stored CR, so a large rise is a large XP rise.")
        w("")
        w("| creature | resref | stored | computed | change | top term | top item (gp) | CRAdjust | slots | loot class now -> after | areas |")
        w("|---|---|---|---|---|---|---|---|---|---|---|")
        for rr in sorted(rrs, key=lambda x: (-abs(drift[x]["calc"] - drift[x]["stored"]), x)):
            r = drift[rr]
            ks = [k for k in cls0 if k[1] == rr]
            areas = sorted({a for a, _ in ks})
            c0 = collections.Counter(cls0[k] for k in ks)
            c1 = collections.Counter(cls1[k] for k in ks)
            fmt = lambda c: "/".join("%s %d" % (k or "-", n) for k, n in sorted(c.items(), key=lambda x: str(x[0]))) or "-"  # noqa: E731
            top = ("`%s` %s" % (r["top_item"][0], "{:,}".format(r["top_item"][1]))) if r["top_item"] else "-"
            w("| %s | `%s` | %g | %g | %+.0f%% | %s | %s | %+d | %d | %s -> %s | %s |" % (
                name(rr), rr, r["stored"], r["calc"], 100.0 * (r["calc"] - r["stored"]) / max(1.0, r["stored"]),
                r["dominant"], top, r["cr_adjust"],
                len(placements.get(rr, [])) + len(enc_slots.get(rr, [])),
                fmt(c0), fmt(c1), ", ".join("`%s`" % a for a in areas[:4]) + (" ..." if len(areas) > 4 else "")))
        w("")

    w("## Area loot levels after a full resync")
    w("")
    if moved:
        w("| area | level now | after | chests |")
        w("|---|---|---|---|")
        chests = {a: e.get("chests", 0) for a, e in data["area_levels"]["areas"].items()}
        for a in sorted(moved, key=lambda a: (-(chests.get(a) or 0), a)):
            w("| %s (`%s`) | %s | %s | %d |" % (bi.area_name(a).replace("|", "/"), a, lv0.get(a, "-"),
                                               lv1.get(a, "-"), chests.get(a) or 0))
    else:
        w("None.")
    w("")
    return "\n".join(L)


def main():
    ap = argparse.ArgumentParser(description=__doc__,
                                 formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--write", action="store_true", help="regenerate CLAUDE-creature-cr-audit.md")
    a = ap.parse_args()
    text = report(run_nwn_cr()) + "\n"
    if a.write:
        AUDIT.write_text(text, encoding="utf-8")
        print("wrote %s" % AUDIT.name)
    else:
        start = text.find("## Summary")
        print(text[start:text.find("\n## ", start + 5)])


if __name__ == "__main__":
    main()
