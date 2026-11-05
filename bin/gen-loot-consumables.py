#!/usr/bin/env python3
"""gen-loot-consumables.py - the item pools a loot container draws from.

Loot Overhaul Phase 3 (roadmap rng-based-gear-diablo-world-of-warcraft-style).
Besides rolled gear, a chest holds gold - sometimes paid as precious gems - and
a few consumables.  Both pools are plain JSON the admin reviews and edits:

    loot/consumables.json   {resref, family, value, min_level, max_level, weight, stack}
    loot/treasure.json      {resref, name, value} - plain valuable gems

``--draft`` builds both from module-index/item_index.json (gitignored; run the
wiki once): every obtainable potion, scroll, kit, wand and ammunition stack
that a store sells or a container holds - not only the donation chest's list -
and every obtainable gem with a price and no item properties.  It skips
anything Plot or Cursed, anything only a creature carries (boss signature
ammunition stays the boss's), and anything a script looks up by resref or
tag, or a conversation passes as a script parameter (quest items).  A consumable's level window comes from what one
drop is worth against VALUE_CAP: it appears from the first level whose cap
covers it, and stops once it is worth less than 1/RETIRE of the cap.

``--refresh-items`` snapshots the stock (non-unpacked/) items the pools name
into loot/_items.json, so the build gate needs no NWN install - the same idea
as loot/_costs.json.

    python3 bin/gen-loot-consumables.py                 # check _items.json covers the pools
    python3 bin/gen-loot-consumables.py --draft         # write both drafts (refuses to overwrite)
    python3 bin/gen-loot-consumables.py --draft --force # ...even over a reviewed pool
    python3 bin/gen-loot-consumables.py --refresh-items # snapshot stock items not yet in it (needs NWN;
                                                    #   --full re-reads them all)

After either write: python3 bin/gen-loot-tables.py --apply, then a clean repack.
"""

from __future__ import annotations

import argparse
import importlib.util
import json
import re
import subprocess
import sys
import tempfile
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
import loot_model as lm  # noqa: E402

ROOT = lm.ROOT

_spec = importlib.util.spec_from_file_location("gen_loot_tables", ROOT / "bin" / "gen-loot-tables.py")
gen = importlib.util.module_from_spec(_spec)
_spec.loader.exec_module(gen)

# item_index base_item label -> (family, draft stack [min, max])
FAMILIES = {
    "potions": ("potion", [1, 2]),
    "spellscroll": ("scroll", [1, 1]),
    "healerskit": ("kit", [1, 1]),
    "trapkit": ("kit", [1, 1]),
    "thievestools": ("kit", [1, 1]),
    "magicwand": ("wand", [1, 1]),
    "grenade": ("thrown", [1, 3]),
    "arrow": ("ammo", [10, 30]),
    "bolt": ("ammo", [10, 30]),
    "bullet": ("ammo", [10, 30]),
    "dart": ("thrown", [5, 20]),
    "shuriken": ("thrown", [5, 20]),
    "throwingaxe": ("thrown", [5, 20]),
}
# Share of all consumable drops each family gets (spread over its items).
SHARE = {"potion": 30, "scroll": 25, "ammo": 20, "kit": 12, "thrown": 8, "wand": 5}
# Most one consumable drop may be worth at a loot level (gp).
VALUE_CAP = {1: 200, 10: 1500, 20: 5000, 30: 12000, 40: 30000, 50: 60000, 60: 120000}
RETIRE = 300
# Tags kept out of the pools on purpose: Rogue's Gem is "only procured through the
# sneakiest means" (pickpocketing) - a chest must not hand it out.
EXCLUDE_TAGS = {"roguegem"}
# Stock treasure scripts list every potion and gem, and the Jasperre AI checks its own
# potions by tag; none of them are quest scripts.
IGNORE_SCRIPTS = re.compile(r"^(nw_o2_|x0_i0_treasure|x2_inc_treasure|loot_|j_inc_|j_ai_)", re.I)


def _cap(level):
    return lm.interp_points(sorted([k, v] for k, v in VALUE_CAP.items()), level)


def _item_index():
    p = ROOT / "module-index" / "item_index.json"
    if not p.exists():
        sys.exit("module-index/item_index.json missing - run the wiki once")
    d = json.loads(p.read_text())
    return d["items"] if isinstance(d, dict) else d


LOOKUP = re.compile(r"GetItemPossessedBy|HasItem|GetTag\s*\(|GetResRef\s*\(|TakeItem|"
                    r"RemoveItem|GetNearestObjectByTag|GetObjectByTag", re.I)


def _referenced():
    """Quoted strings on script lines that LOOK an item up (GetItemPossessedBy,
    GetTag(...) ==, GetResRef(...) ==, ...) plus every conversation script
    parameter, lower-cased.  A resref or tag in here is a quest item.  Lines
    that only CREATE an item (a prize wheel, the donations stocking) do not
    count: those are rewards, and being a reward does not make it a quest item."""
    names = set()
    for p in lm.UNPACKED.glob("*.nss"):
        if IGNORE_SCRIPTS.match(p.name):
            continue
        for ln in p.read_text(errors="replace").splitlines():
            if LOOKUP.search(ln):
                names.update(m.lower() for m in re.findall(r'"([^"\n]{1,40})"', ln))
    for p in lm.UNPACKED.glob("*.dlg.json"):
        txt = p.read_text(errors="replace")
        for m in re.finditer(r'"Value":\s*\{"type":\s*"cexostring",\s*"value":\s*"([^"]{1,40})"', txt):
            names.add(m.group(1).lower())
    return names


def _obtainable_freely(it):
    return it.get("accessible") and any(
        s.startswith("Sold at") or s.startswith("In container") for s in it.get("sources", []))


def _tag_of(resref, facts):
    u = lm.load_uti(resref)
    if u is not None:
        return str(lm.gff(u, "Tag", "") or "").lower()
    return str((facts or {}).get("tag", "")).lower()


def draft(force):
    items = _item_index()
    data = lm.load_data()
    stock = data.get("items", {}).get("items", {})
    refs = _referenced()
    gone = set(data.get("items", {}).get("missing", []))
    cons, gems = [], []
    seen_tags = set()
    skipped = {"same tag": 0, "quest": 0, "plot": 0, "carried-only": 0, "too dear": 0, "no price": 0, "props": 0}
    for it in sorted(items, key=lambda i: (float(i.get("cost_gp") or 0), i["resref"])):
        rr = it["resref"].lower()
        b = it.get("base_item")
        if b not in FAMILIES and b != "gem":
            continue
        if len(rr) > 16 or rr in gone:
            continue
        if b == "gem":
            if not it.get("accessible"):
                continue
        elif not _obtainable_freely(it):
            skipped["carried-only"] += 1
            continue
        tag = _tag_of(rr, stock.get(rr))
        if tag in EXCLUDE_TAGS:
            continue
        if rr in refs or tag in refs:
            skipped["quest"] += 1
            continue
        # One entry per tag: the module's bulk packs (it_mpotion029 1x /
        # it_mpotion032 10x) share the stock tag, and each copy would add weight.
        if tag and tag in seen_tags:
            skipped["same tag"] += 1
            continue
        seen_tags.add(tag)
        u = lm.load_uti(rr)
        if u is not None:
            plot = lm.gff(u, "Plot", 0) or lm.gff(u, "Cursed", 0)
            nprops = len(lm.gff(u, "PropertiesList", []) or [])
            stack = int(lm.gff(u, "StackSize", 1) or 1)
        elif rr in stock:
            f = stock[rr]
            plot, nprops, stack = f["plot"] or f["cursed"], f["props"], f["stack"]
        else:
            # Not snapshotted yet: --refresh-items, then --draft --force.
            plot, nprops, stack = 0, 0, 1
        if plot:
            skipped["plot"] += 1
            continue
        cost = int(float(it.get("cost_gp") or 0))
        if cost <= 0:
            skipped["no price"] += 1
            continue
        if b == "gem":
            if nprops:
                skipped["props"] += 1
                continue
            gems.append({"resref": rr, "name": it.get("name", "").strip(), "value": cost})
            continue
        fam, st = FAMILIES[b]
        unit = max(1, cost // max(1, stack))
        drop = unit * st[1]
        lo = next((lv for lv in range(1, lm.MAX_LEVEL + 1) if _cap(lv) >= drop), None)
        if lo is None:
            skipped["too dear"] += 1
            continue
        hi = max((lv for lv in range(1, lm.MAX_LEVEL + 1) if drop * RETIRE >= _cap(lv)), default=lo)
        hi = min(lm.MAX_LEVEL, max(hi, lo + 9))
        cons.append({"resref": rr, "name": it.get("name", "").strip(), "family": fam,
                     "value": drop, "min_level": lo, "max_level": hi, "stack": st})
    n_fam = {}
    for c in cons:
        n_fam[c["family"]] = n_fam.get(c["family"], 0) + 1
    for c in cons:
        c["weight"] = max(1, round(SHARE[c["family"]] * 100 / n_fam[c["family"]]))
    cons.sort(key=lambda c: (c["family"], c["min_level"], c["resref"]))
    gems.sort(key=lambda g: (g["value"], g["resref"]))

    out_c = lm.LOOT_DIR / "consumables.json"
    out_t = lm.LOOT_DIR / "treasure.json"
    for p in (out_c, out_t):
        if p.exists() and not force:
            old = json.loads(p.read_text())
            if old.get("items") or old.get("gems"):
                sys.exit("%s already holds a pool - it may have been reviewed. "
                         "Re-run with --force to overwrite." % p.relative_to(ROOT))
    out_c.write_text(dump_pool(
        "DRAFT by bin/gen-loot-consumables.py --draft (admin review pending). The consumables "
        "a loot container may hold (profile 'consumables' count). Edit freely: an entry is "
        "eligible from min_level to max_level, picked by weight, created as a stack of "
        "stack[0]..stack[1]. value = one drop's worth at the top of its stack (informational). "
        "Remove anything that should not drop, then gen-loot-tables.py --apply.",
        "items", cons))
    out_t.write_text(dump_pool(
        "DRAFT by bin/gen-loot-consumables.py --draft (admin review pending). Plain valuable "
        "gems a container may pay its gold in (profile gem_chance): up to 3 gems whose value "
        "fits the gold amount, the rest as gold. value = gp the payout counts it as. No item "
        "properties, not Plot, not named by any script.",
        "gems", gems))
    print("wrote %s (%d) and %s (%d); skipped %s"
          % (out_c.relative_to(ROOT), len(cons), out_t.relative_to(ROOT), len(gems),
             ", ".join("%s %d" % kv for kv in skipped.items())))
    print("now: python3 bin/gen-loot-consumables.py --refresh-items")


def dump_pool(doc, key, rows):
    lines = ["{", '  "_doc": %s,' % json.dumps(doc), '  "%s": [' % key]
    for i, r in enumerate(rows):
        lines.append("    %s%s" % (json.dumps(r, separators=(", ", ": ")), "," if i < len(rows) - 1 else ""))
    lines += ["  ]", "}"]
    return "\n".join(lines) + "\n"


def _old_missing():
    p = lm.LOOT_DIR / "_items.json"
    return json.loads(p.read_text()).get("missing", []) if p.exists() else []


def _pool_resrefs():
    rr = set()
    for name, key in (("consumables.json", "items"), ("treasure.json", "gems")):
        p = lm.LOOT_DIR / name
        if p.exists():
            rr.update(r["resref"] for r in json.loads(p.read_text())[key])
    return sorted(rr)


def refresh_items(full=False):
    gff_tool = gen._tool("nwn_gff")
    cat = gen._tool("nwn_resman_cat")
    home = gen._server_env().get("NWN_HOME_DIR", "").replace("$HOME", str(Path.home()))
    ifo = json.loads((lm.UNPACKED / "module.ifo.json").read_text())
    haks = [h["Mod_Hak"]["value"] for h in ifo["Mod_HakList"]["value"]]
    erfs = [str(Path(home) / "hak" / (h + ".hak")) for h in reversed(haks)]
    erfs = [e for e in erfs if Path(e).exists()]
    old = {}
    p_old = lm.LOOT_DIR / "_items.json"
    if p_old.exists() and not full:
        old = json.loads(p_old.read_text()).get("items", {})
    out = {}
    missing = []
    with tempfile.TemporaryDirectory() as td:
        for rr in _pool_resrefs():
            if lm.load_uti(rr) is not None:
                continue
            if rr in old:
                out[rr] = old[rr]
                continue
            f = Path(td) / (rr + ".uti")
            with f.open("wb") as fh:
                r = subprocess.run([cat, "--quiet", "--erfs", ",".join(erfs), rr + ".uti"], stdout=fh)
            if r.returncode != 0 or f.stat().st_size == 0:
                missing.append(rr)
                continue
            j = subprocess.run([gff_tool, "-i", str(f), "-k", "json"], capture_output=True, text=True)
            u = json.loads(j.stdout)
            out[rr] = {"base": lm.gff(u, "BaseItem"), "cost": int(lm.gff(u, "Cost", 0) or 0),
                       "stack": int(lm.gff(u, "StackSize", 1) or 1),
                       "plot": int(lm.gff(u, "Plot", 0) or 0), "cursed": int(lm.gff(u, "Cursed", 0) or 0),
                       "props": len(lm.gff(u, "PropertiesList", []) or []),
                       "tag": str(lm.gff(u, "Tag", "") or "")}
    doc = {"_doc": "GENERATED by bin/gen-loot-consumables.py --refresh-items from the game's "
                   "resources (stock + the module's haks). Do not edit. Facts about the stock "
                   "items the loot pools name, so the build gate needs no NWN install.",
           "items": out, "missing": sorted(set(missing) | (set() if full else set(_old_missing())))}
    p = lm.LOOT_DIR / "_items.json"
    p.write_text(json.dumps(doc, indent=1, sort_keys=True) + "\n")
    print("wrote %s (%d stock items)" % (p.relative_to(ROOT), len(out)))
    if missing:
        print("not found anywhere (recorded in _items.json 'missing'; --draft skips them, "
              "remove them from a reviewed pool): " + ", ".join(missing))
        return 1
    return 0


def check():
    data = lm.load_data()
    gap = [rr for rr in _pool_resrefs() if lm.item_facts(data, rr) is None]
    if gap:
        print("not in unpacked/ or loot/_items.json - run --refresh-items: " + ", ".join(gap))
        return 1
    print("ok: %d pool items resolved" % len(_pool_resrefs()))
    return 0


def main():
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--draft", action="store_true")
    ap.add_argument("--force", action="store_true")
    ap.add_argument("--refresh-items", action="store_true")
    ap.add_argument("--full", action="store_true", help="with --refresh-items: re-read every stock item")
    a = ap.parse_args()
    if a.draft:
        draft(a.force)
    if a.refresh_items:
        return refresh_items(a.full)
    return check()


if __name__ == "__main__":
    sys.exit(main())
