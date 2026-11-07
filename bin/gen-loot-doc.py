#!/usr/bin/env python3
"""gen-loot-doc.py - the generated tables on the Rolled Loot wiki page.

docs.manual/Customizations/Loot.html carries two blocks this script owns:

    <!-- loot:rarity -->  ... <!-- /loot:rarity -->    the rarity tiers
    <!-- loot:affixes --> ... <!-- /loot:affixes -->   every enchantment that can
                                                       roll, per item category,
                                                       with its range by loot level

Both are rendered from loot/*.json through bin/loot_model.py (the same model
the loot gate and loot-sim use), so the page can never disagree with the data.
What a cost-table row means in game ("1d6", "-30%", "SR 22") comes from
loot/_costs.json "cost_labels" (snapshotted by gen-loot-tables.py
--refresh-costs), so this needs no NWN install.  Never hand-edit inside the
markers: bin/gen-loot-tables.py --apply rewrites them, and
tests/check_loot_tables.py fails the repack when they are stale.

    python3 bin/gen-loot-doc.py            # dry run: say whether the page is stale
    python3 bin/gen-loot-doc.py --apply    # rewrite the blocks
    python3 bin/gen-loot-doc.py --check    # exit 1 when stale (what the gate does)

After --apply, run python3 bin/gen-customizations-hub.py so the hub's search
index picks up the new text.
"""

import argparse
import html
import re
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
import loot_model as lm  # noqa: E402

ROOT = lm.ROOT
PAGE = ROOT / "docs.manual" / "Customizations" / "Loot.html"
LEVELS = (1, 20, 40, 50, 60)

CAT_TITLES = {
    "melee": "Melee weapons",
    "ranged": "Ranged weapons",
    "armor": "Armour",
    "shield": "Shields",
    "jewelry": "Jewellery (rings and amulets)",
    "wearable": "Other wearables (belts, boots, cloaks, gloves, helmets, bracers)",
    "caster": "Magic staves",
}
COLOR_NAMES = {"COLOR_WHITE": "white", "COLOR_GREEN": "green", "COLOR_BLUE": "blue",
               "COLOR_PURPLE": "purple", "COLOR_ORANGE": "orange"}


class DocError(Exception):
    pass


def esc(s):
    return html.escape(str(s), quote=False)


def _int(x):
    try:
        return int(float(x))
    except (TypeError, ValueError):
        return None


def _signed(n):
    return "%+d" % n


def fmt_value(data, aff, row):
    """What ladder row ``row`` of ``aff`` gives in game, as a short string."""
    t = aff["type"]
    d = data["costs"]["itempropdef"].get(str(t)) or {}
    table = d.get("cost_table")
    if not table:
        return "yes"
    lab = data["costs"].get("cost_labels", {}).get(table, {}).get(str(row))
    if lab is None:
        raise DocError("affix %r: cost row %s of %s has no label in loot/_costs.json - "
                       "re-run python3 bin/gen-loot-tables.py --refresh-costs"
                       % (aff["id"], row, table))
    if "NumDice" in lab and "Die" in lab:                 # damage bonus, massive criticals
        nd, die = _int(lab["NumDice"]), _int(lab["Die"])
        return "+%d" % die if nd == 0 else "%dd%d" % (nd, die)
    if t in (20, 24):                                     # immunity / vulnerability %
        return "%d%%" % _int(lab["Value"])
    if t == 84:                                           # arcane spell failure
        return "%+d%%" % _int(lab["Value"])
    if t == 23:                                           # resistance N/-
        return "%d/-" % _int(lab["Amount"])
    if t == 22:                                           # DR soak/+enh (iprp_protection row n = +n+1)
        return "%d/+%d" % (_int(lab["Amount"]), (aff.get("sub") or 0) + 1)
    if t == 39:
        return "SR %d" % _int(lab["Value"])
    if t == 13:
        m = re.search(r"(\d+)", lab.get("Label", ""))
        return "level %s" % (m.group(1) if m else row)
    if "Value" in lab and _int(lab["Value"]) is not None and _int(lab["Value"]) < 0:
        return str(_int(lab["Value"]))                    # penalties
    if t in lm.NEGATIVE_TYPES:
        n = _int(lab.get("Label")) or _int(lab.get("Value")) or row
        return "-%d" % abs(n)
    n = _int(lab.get("Label"))
    if n is None:
        n = _int(lab.get("Value"))
    if n is None:
        raise DocError("affix %r: cannot read cost row %s of %s (%r)" % (aff["id"], row, table, lab))
    return _signed(n)


def fmt_range(data, aff, level):
    if level < aff.get("min_level", 1):
        return "&mdash;"
    lo, hi = lm.affix_window(aff, level)
    a = fmt_value(data, aff, aff["ladder"][lo])
    b = fmt_value(data, aff, aff["ladder"][hi])
    return esc(a) if a == b else "%s to %s" % (esc(a), esc(b))


def _pct(x):
    if x >= 10:
        return "%d%%" % round(x)
    if x >= 1:
        return "%.1f%%" % x
    return "%.2f%%" % x


def _gp(n):
    return "{:,}".format(n)


def rarity_block(data):
    tiers = data["rarity"]["tiers"]
    anyd = lm.rarity_dist(data, 0)
    boss_floor = int(data["sources"]["profiles"].get("boss", {}).get("rarity_floor", 0))
    bossd = lm.rarity_dist(data, boss_floor)
    out = ['<table class="data change-table">',
           "  <thead><tr><th>Rarity</th><th>Name colour</th><th>Enchantments</th>"
           "<th>Strength roll</th><th>Sockets</th><th>Drawback chance</th>"
           "<th>How often (any drop)</th><th>How often (boss drop)</th></tr></thead>",
           "  <tbody>"]
    for i, t in enumerate(tiers):
        lo, hi = t["affixes"]
        en = str(lo) if lo == hi else "%d&ndash;%d" % (lo, hi)
        bias = int(t.get("roll_bias", 0))
        rolls = "1 roll" if bias == 0 else "best of %d" % (bias + 1)
        slo, shi = t.get("sockets", [0, 0])
        so = str(slo) if slo == shi else "%d&ndash;%d" % (slo, shi)
        out.append("    <tr><td>%s</td><td>%s</td><td>%s</td><td>%s</td><td>%s</td><td>%s</td>"
                   "<td>%s</td><td>%s</td></tr>"
                   % (esc(t["name"]), COLOR_NAMES.get(t["color"], t["color"]), en, rolls, so,
                      _pct(t.get("downside_chance", 0) / 10.0), _pct(anyd[i] * 100),
                      _pct(bossd[i] * 100) if bossd[i] else "&mdash;"))
    out += ["  </tbody>", "</table>", ""]
    out.append('<p>The gold ceiling (the most an item\'s random enchantments may be worth, '
               'in gold) by loot level. A roll with a drawback gets %d%% more.</p>'
               % int(tiers[0].get("downside_budget_pct", 0)))
    out.append('<table class="data change-table">')
    out.append("  <thead><tr><th>Rarity</th>%s</tr></thead>"
               % "".join("<th>Level %d</th>" % lv for lv in LEVELS))
    out.append("  <tbody>")
    for t in tiers:
        out.append("    <tr><td>%s</td>%s</tr>"
                   % (esc(t["name"]),
                      "".join("<td>%s gp</td>" % _gp(lm.rarity_budget(t, lv)) for lv in LEVELS)))
    out += ["  </tbody>", "</table>"]
    return "\n".join(out)


def _affix_table(data, rows, share):
    out = ['<table class="data change-table">',
           "  <thead><tr><th>Enchantment</th><th>Share</th><th>From level</th>%s</tr></thead>"
           % "".join("<th>Level %d</th>" % lv for lv in LEVELS),
           "  <tbody>"]
    for a in rows:
        out.append("    <tr><td>%s</td><td>%s</td><td>%d</td>%s</tr>"
                   % (esc(a["name"]), _pct(share[a["id"]]), int(a.get("min_level", 1)),
                      "".join("<td>%s</td>" % fmt_range(data, a, lv) for lv in LEVELS)))
    out += ["  </tbody>", "</table>"]
    return out


def affix_block(data):
    affixes = [a for a in data["affixes"]["affixes"] if a.get("weight", 0) > 0]
    missing = [a["id"] for a in affixes if not a.get("name")]
    if missing:
        raise DocError("affix(es) with no \"name\" in loot/affixes.json: " + ", ".join(missing))
    out = []
    for cat in lm.CATEGORIES:
        rows = [a for a in affixes if a["role"] == "upside" and cat in a["cats"]]
        if not rows:
            continue
        total = float(sum(a["weight"] for a in rows))
        share = {a["id"]: 100.0 * a["weight"] / total for a in rows}
        rows.sort(key=lambda a: (-a["weight"], a["name"]))
        out.append("<details>")
        out.append("<summary><strong>%s</strong> &middot; %d enchantments</summary>"
                   % (esc(CAT_TITLES.get(cat, cat)), len(rows)))
        out += _affix_table(data, rows, share)
        out.append("</details>")
    downs = [a for a in affixes if a["role"] == "downside"]
    if downs:
        total = float(sum(a["weight"] for a in downs))
        share = {a["id"]: 100.0 * a["weight"] / total for a in downs}
        downs.sort(key=lambda a: (-a["weight"], a["name"]))
        out.append("<details>")
        out.append("<summary><strong>Drawbacks</strong> &middot; %d, on any kind of item "
                   "(attack penalty on weapons only)</summary>" % len(downs))
        out += _affix_table(data, downs, share)
        out.append("</details>")
    return "\n".join(out)


BLOCKS = (("loot:rarity", rarity_block), ("loot:affixes", affix_block))


def render(text, data):
    for name, fn in BLOCKS:
        pat = re.compile(r"(<!-- %s -->\n)(.*?)(<!-- /%s -->)" % (re.escape(name), re.escape(name)),
                         re.S)
        if not pat.search(text):
            raise DocError("%s has no <!-- %s --> ... <!-- /%s --> block"
                           % (PAGE.relative_to(ROOT), name, name))
        body = fn(data) + "\n"
        text = pat.sub(lambda m: m.group(1) + body + m.group(3), text, count=1)
    return text


def problems(data=None):
    """[] when the page is up to date, else one-line problems (for the gate)."""
    data = data or lm.load_data()
    if not PAGE.exists():
        return ["%s is missing" % PAGE.relative_to(ROOT)]
    cur = PAGE.read_text(encoding="utf-8")
    try:
        new = render(cur, data)
    except DocError as e:
        return [str(e)]
    if new != cur:
        return ["%s loot tables are stale. Re-run: python3 bin/gen-loot-doc.py --apply "
                "(or gen-loot-tables.py --apply), then python3 bin/gen-customizations-hub.py"
                % PAGE.relative_to(ROOT)]
    return []


def apply(data=None):
    """Rewrite the blocks; True when the page changed."""
    data = data or lm.load_data()
    cur = PAGE.read_text(encoding="utf-8")
    new = render(cur, data)
    if new == cur:
        return False
    PAGE.write_text(new, encoding="utf-8")
    return True


def main():
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--apply", action="store_true", help="rewrite the generated blocks")
    ap.add_argument("--check", action="store_true", help="exit 1 when the page is stale")
    a = ap.parse_args()
    data = lm.load_data()
    if a.apply:
        try:
            changed = apply(data)
        except DocError as e:
            print("gen-loot-doc: " + str(e))
            return 1
        print("gen-loot-doc: %s %s" % ("wrote" if changed else "OK, unchanged",
                                       PAGE.relative_to(ROOT)))
        if changed:
            print("  now run: python3 bin/gen-customizations-hub.py")
        return 0
    probs = problems(data)
    for p in probs:
        print("gen-loot-doc: " + p)
    if not probs:
        print("gen-loot-doc: OK (%s)" % PAGE.relative_to(ROOT))
    return 1 if (probs and a.check) else 0


if __name__ == "__main__":
    sys.exit(main())
