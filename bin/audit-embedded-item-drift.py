#!/usr/bin/env python3
"""Audit item copies embedded in placed creatures against their item blueprints.

WHY THIS EXISTS
    A placed creature in <area>.git.json does not reference its gear: it embeds
    a FULL COPY of every item it carries (properties, tag, name, base item, the
    lot). A creature blueprint (.utc) only names its items by resref. So:

      * until a placed creature first dies after a reboot, it wears, fights
        with and drops its EMBEDDED copies;
      * se_respawn_inc.nss recreates it from the .utc, which builds every item
        fresh from its .uti -- every respawn after that, all day, carries the
        BLUEPRINT copies, and the wiki shows those too.

    Wherever the two differ, the first kill of the day is a different creature
    with different loot. Anaralia's "better robe on the second kill" was this
    (roadmap anaralia-spider-queen-second-drop); so were Card Mennard's two
    swords and the White Hand Destroyer's scythe, whose placed copy carried the
    tag Theoden checks while the blueprint did not.

    tests/check_divergent_creatures.py never saw it: it compares gear by slot,
    resref and the Dropable flag, and never opens the embedded item. The drift
    is inherited from the toolset era (editing an item inside a placed
    creature's inventory, or a numeric resref later reused for a different
    item), not from this repo's bulk edits -- nothing was in sync at the first
    import and drifted after.

WHAT IT WRITES
    tests/embedded_item_drift.json        the decision file + the gate's burn-down
    CLAUDE-embedded-item-drift-audit.md   the same rows, readable

    One row per (creature blueprint, slot or inventory, item resref) where any
    placed copy differs from <resref>.uti.json. Items with no local .uti (stock)
    cannot be compared and are not listed.

RECOMMENDATION (the admin decides; see `decision`)
    Favour the STRONGER copy, valued with the NWN cost formula
    (bin/loot_model.py CostModel). Overrides, in order:
      1. the blueprint's base item cannot go in the slot the creature wears it in
         (an arrow in a ring slot)                          -> placed
      2. a script tests the placed copy's tag but not the blueprint's -> placed
      3. only description / appearance differ (cosmetic)  -> blueprint
      4. a tie                                            -> blueprint
    `placed` means: mint (or reuse) a blueprint from the placed copy and point
    the creature at it. `blueprint` means: resync the placed copies to the .uti.

    python3 bin/audit-embedded-item-drift.py            # summary
    python3 bin/audit-embedded-item-drift.py --write    # rewrite both files,
                                                        # keeping every decision
    Then fill in "decision" ("blueprint" / "placed") per row and run
    bin/fix-embedded-item-drift.py.
"""

import argparse
import collections
import glob
import hashlib
import json
import os
import re
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
UNPACKED = os.path.join(ROOT, "unpacked")
DECISIONS = os.path.join(ROOT, "tests", "embedded_item_drift.json")
DOC = os.path.join(ROOT, "CLAUDE-embedded-item-drift-audit.md")
sys.path.insert(0, os.path.join(ROOT, "bin"))

# Keys only a placed copy has (where it sits, whether it drops) and the
# blueprint-only keys. Neither is item content.
INSTANCE_ONLY = {"Dropable", "Pickpocketable", "XPosition", "YPosition",
                 "ZPosition", "XOrientation", "YOrientation", "Repos_PosX",
                 "Repos_Posy", "Repos_PosY", "__struct_id", "EquippedRes",
                 "InventoryRes", "TemplateResRef"}
UTI_ONLY = {"Comment", "PaletteID", "__data_type"}
# Cost is a cached figure the toolset derives from the rest; it is stale on
# both sides far too often to mean anything.
DERIVED = {"Cost"}
NOT_CONTENT = INSTANCE_ONLY | UTI_ONLY | DERIVED

STATS = {"PropertiesList", "Charges", "StackSize", "Plot", "Cursed"}
IDENTITY = {"Tag", "LocalizedName", "Identified"}
CLASS_ORDER = ("different-item", "stats", "identity", "cosmetic")

SLOT_NAMES = {1: "head", 2: "chest", 4: "boots", 8: "arms", 16: "right hand",
              32: "left hand", 64: "cloak", 128: "left ring", 256: "right ring",
              512: "neck", 1024: "belt", 2048: "arrows", 4096: "bullets",
              8192: "bolts", 16384: "creature weapon L", 32768: "creature weapon R",
              65536: "creature weapon B", 131072: "creature hide"}


def fld(s, k):
    v = s.get(k) if isinstance(s, dict) else None
    return v.get("value") if isinstance(v, dict) else None


def loc(s, k):
    v = fld(s, k)
    if isinstance(v, dict):
        return v.get("0") or (f"<tlk {v['id']}>" if "id" in v else "")
    return v or ""


def props(item):
    out = []
    for p in fld(item, "PropertiesList") or []:
        sub = fld(p, "Subtype")
        if sub == 65535:      # a blank Subtype is stored as either 0 or 65535
            sub = 0
        out.append((fld(p, "PropertyName"), sub, fld(p, "CostTable"),
                    fld(p, "CostValue"), fld(p, "Param1"), fld(p, "Param1Value"),
                    fld(p, "ChanceAppear")))
    return sorted(out, key=lambda t: tuple(-1 if x is None else x for x in t))


def content(item):
    """The comparable content of an item struct, placed or blueprint.

    NWN:EE stores extended (16-bit) model parts in parallel `x` fields --
    `xModelPart1`, `xArmorPart_Torso`, label cut to GFF's 16 characters
    (`xArmorPart_LBice`). A newer toolset writes them on save, so placed copies
    carry them and older blueprints do not. One that only repeats its base
    field is not a difference; one that disagrees with it is kept.
    """
    raw = {k: (v.get("value") if isinstance(v, dict) else v) for k, v in item.items()}
    base_of = {("x" + k)[:16]: k for k in raw if not k.startswith("x")}
    out = {}
    for k, v in raw.items():
        if k in NOT_CONTENT:
            continue
        if k in base_of and k.startswith("x") and raw.get(base_of[k]) == v:
            continue
        out[k] = props(item) if k == "PropertiesList" else v
    return out


def fingerprint(item):
    blob = json.dumps(content(item), sort_keys=True, ensure_ascii=False)
    return hashlib.sha1(blob.encode("utf-8")).hexdigest()[:12]


def differing(a, b):
    ca, cb = content(a), content(b)
    return sorted(k for k in set(ca) | set(cb) if ca.get(k) != cb.get(k))


def summarize(keys):
    """Fold the armour-part / colour / model-part families into one word each."""
    out, fam = [], set()
    for k in keys:
        base = k[1:] if k.startswith("x") and k[1:2].isupper() else k
        if base.startswith("ArmorPart_"):
            fam.add("armour parts")
        elif base.endswith("Color"):
            fam.add("colours")
        elif base.startswith("ModelPart"):
            fam.add("model")
        elif k in ("Description", "DescIdentified"):
            fam.add("description")
        else:
            out.append(k)
    return out + sorted(fam)


def classify(keys):
    keys = set(keys)
    if "BaseItem" in keys:
        return "different-item"
    if keys & STATS:
        return "stats"
    if keys & IDENTITY:
        return "identity"
    return "cosmetic"


def read_2da(path):
    rows = {}
    lines = open(path, encoding="latin-1").read().splitlines()
    cols = None
    for line in lines[1:]:
        toks = re.findall(r'"[^"]*"|\S+', line)
        if not toks:
            continue
        if cols is None:
            cols = toks
            continue
        if toks[0].isdigit():
            rows[int(toks[0])] = dict(zip(cols, toks[1:]))
    return rows


class Valuer:
    def __init__(self):
        import loot_model as lm
        self.cm = lm.CostModel(lm.load_data()["costs"])
        self.neg = lm.NEGATIVE_TYPES
        self.base_rows = read_2da(os.path.join(ROOT, "hak_2da", "baseitems.2da"))

    def value(self, item):
        triples = [(t, s, c) for t, s, _ct, c, *_ in props(item)]
        base = fld(item, "BaseItem")
        try:
            return self.cm.item_value(base, triples)
        except KeyError:
            # Not a loot base, so no base cost/multiplier on file: compare on
            # the properties alone (both sides of a same-base pair alike).
            pos = sum(self.cm.prop_cost(t, s, c) for t, s, c in triples if t not in self.neg)
            neg = sum(self.cm.prop_cost(t, s, c) for t, s, c in triples if t in self.neg)
            return int(1000 * (pos * pos - neg * neg))

    def fits_slot(self, base, slot):
        row = self.base_rows.get(base)
        if not row:
            return True          # unknown base: do not claim it cannot fit
        raw = row.get("EquipableSlots", "****")
        try:
            return bool(int(raw, 16) & slot)
        except ValueError:
            return False


def script_tags():
    """Every string literal in the module's scripts (tags scripts test)."""
    found = set()
    for path in glob.glob(os.path.join(UNPACKED, "*.nss")):
        found.update(re.findall(r'"([^"\n]{1,64})"',
                                open(path, encoding="latin-1").read()))
    return found


def scan():
    """Every drifting pair: key -> row (without recommendation)."""
    utis = {}

    def uti(r):
        if r not in utis:
            p = os.path.join(UNPACKED, f"{r}.uti.json")
            utis[r] = json.load(open(p, encoding="utf-8")) if os.path.exists(p) else None
        return utis[r]

    names = {}
    pairs = {}
    for gpath in sorted(glob.glob(os.path.join(UNPACKED, "*.git.json"))):
        area = os.path.basename(gpath)[:-len(".git.json")]
        for c in fld(json.load(open(gpath, encoding="utf-8")), "Creature List") or []:
            cr = fld(c, "TemplateResRef")
            names.setdefault(cr, (loc(c, "FirstName") + " " + loc(c, "LastName")).strip())
            for lst in ("Equip_ItemList", "ItemList"):
                for it in fld(c, lst) or []:
                    r = fld(it, "TemplateResRef")
                    u = uti(r) if r else None
                    if u is None or fingerprint(it) == fingerprint(u):
                        continue
                    where = (f"equipped:{it.get('__struct_id')}"
                             if lst == "Equip_ItemList" else "inventory")
                    key = f"{cr}|{where}|{r}"
                    row = pairs.setdefault(key, {
                        "creature": cr, "where": where, "item": r,
                        "areas": set(), "placements": 0, "droppable": False,
                        "variants": {}, "_uti": u})
                    row["areas"].add(area)
                    row["placements"] += 1
                    row["droppable"] |= fld(it, "Dropable") == 1
                    row["variants"].setdefault(fingerprint(it), it)
    utcs = {}
    for row in pairs.values():
        row["creature_name"] = names.get(row["creature"], "")
        cr = row["creature"]
        if cr not in utcs:
            p = os.path.join(UNPACKED, f"{cr}.utc.json")
            utcs[cr] = json.load(open(p, encoding="utf-8")) if os.path.exists(p) else None
        row["utc_form"], row["utc_fp"] = utc_entry_form(utcs[cr], row["where"], row["item"])
    return pairs


def utc_entry(utc, where, resref):
    """The creature blueprint's own entry for this slot / inventory item."""
    if utc is None:
        return None
    lst = "Equip_ItemList" if where != "inventory" else "ItemList"
    for e in fld(utc, lst) or []:
        r = fld(e, "EquippedRes") or fld(e, "InventoryRes") or fld(e, "TemplateResRef")
        if r != resref:
            continue
        if where == "inventory" or e.get("__struct_id") == int(where.split(":")[1]):
            return e
    return None


def utc_entry_form(utc, where, resref):
    """("resref" | "embedded" | "none", fingerprint of an embedded copy or None).

    A toolset blueprint names its items (EquippedRes / InventoryRes). Blueprints
    baked by bin/split-divergent-creatures.py instead carry a FULL item struct
    copied from the placement. Whether the engine builds a respawn's item from
    that struct, from its TemplateResRef's .uti, or not at all is unverified
    (roadmap split-blueprint-embedded-items) -- so these rows are flagged.
    """
    e = utc_entry(utc, where, resref)
    if e is None:
        return "none", None
    if "EquippedRes" in e or "InventoryRes" in e:
        return "resref", None
    return "embedded", fingerprint(e)


def recommend(pairs):
    val = Valuer()
    literals = script_tags()
    out = {}
    for key, row in sorted(pairs.items()):
        u = row.pop("_uti")
        variants = row.pop("variants")
        ranked = sorted(variants.items(), key=lambda kv: -val.value(kv[1]))
        cand_fp, cand = ranked[0]
        diff = sorted(set().union(*(differing(v, u) for v in variants.values())))
        cls = classify(diff)
        pv, bv = val.value(cand), val.value(u)
        ptag, btag = fld(cand, "Tag"), fld(u, "Tag")
        slot = int(row["where"].split(":")[1]) if row["where"].startswith("equipped") else None

        if (cls == "different-item" and slot is not None
                and not val.fits_slot(fld(u, "BaseItem"), slot)):
            rec, why = "placed", (f"the blueprint (base item {fld(u, 'BaseItem')}) cannot "
                                  f"be worn in the {SLOT_NAMES.get(slot, slot)} slot")
        elif ptag != btag and ptag in literals and btag not in literals:
            rec, why = "placed", f"a script tests the placed tag {ptag!r}, not {btag!r}"
        elif cls == "cosmetic":
            rec, why = "blueprint", "cosmetic only (description/appearance)"
        elif pv > bv:
            rec, why = "placed", "placed copy is stronger"
        elif bv > pv:
            rec, why = "blueprint", ("blueprint is stronger" if cls != "different-item"
                                     else "blueprint is stronger, but it is another item "
                                          "entirely (reused resref)")
        else:
            rec, why = "blueprint", "equal value: keep what every respawn already has"

        out[key] = {
            "decision": None, "recommend": rec, "reason": why, "class": cls,
            "creature": row["creature"], "creature_name": row["creature_name"],
            "where": row["where"], "item": row["item"],
            "differs": summarize(diff), "droppable": row["droppable"],
            "placements": row["placements"], "areas": sorted(row["areas"]),
            "variants": len(variants),
            "placed_name": loc(cand, "LocalizedName"), "placed_tag": ptag,
            "placed_base": fld(cand, "BaseItem"), "placed_value": pv,
            "blueprint_name": loc(u, "LocalizedName"), "blueprint_tag": btag,
            "blueprint_base": fld(u, "BaseItem"), "blueprint_value": bv,
            "utc_form": row["utc_form"],
            "utc_copy_is_placed": (row["utc_form"] == "embedded"
                                   and set(variants) == {row["utc_fp"]}),
            "candidate_fp": cand_fp, "placed_fps": sorted(variants),
            "blueprint_fp": fingerprint(u),
        }
    return out


def load_decisions():
    try:
        return json.load(open(DECISIONS, encoding="utf-8"))
    except (OSError, ValueError):
        return {"pairs": {}}


def fmt_value(v):
    return f"{v:,}" if v is not None else "?"


def write_doc(rows):
    by = collections.defaultdict(list)
    for k, r in rows.items():
        by[r["class"]].append((k, r))
    creatures = {r["creature"] for r in rows.values()}
    placements = sum(r["placements"] for r in rows.values())
    rec = collections.Counter(r["recommend"] for r in rows.values())
    dec = collections.Counter(r["decision"] for r in rows.values() if r["decision"])
    L = []
    L.append("<!-- GENERATED by bin/audit-embedded-item-drift.py. Re-run it rather "
             "than hand-editing the tables; decisions live in "
             "tests/embedded_item_drift.json. -->\n")
    L.append("# Embedded item drift — placed creature copies vs. item blueprints\n")
    L.append("A placed creature embeds a **full copy** of every item it carries; its "
             "blueprint names items by resref only. Until it first dies after a reboot "
             "it wears and drops the embedded copies. `se_respawn_inc.nss` rebuilds it "
             "from the `.utc`, so **every respawn after that — and the wiki — uses the "
             "`.uti` blueprint**. Each row below is a creature whose first kill of the day "
             "is not the creature players meet the rest of the day.\n")
    L.append("**Why the divergence gate missed it:** `tests/check_divergent_creatures.py` "
             "compares gear by slot, resref and `Dropable`. It never opened the embedded "
             "item. The drift is inherited from the toolset era (an item edited inside a "
             "placed creature's inventory gets an instance-only copy, often with a `…2` tag; "
             "numeric resrefs like `044` were later reused for different items). Nothing in "
             "this repo's own history caused it: no pair was in sync at the first import "
             "(`e1fc8e2f249`) and drifted after.\n")
    L.append(f"**{len(rows)} pairs** on **{len(creatures)} creature blueprints**, "
             f"{placements} placed copies; "
             + ", ".join(f"{len(by[c])} {c}" for c in CLASS_ORDER if by[c])
             + f"; {sum(r['droppable'] for r in rows.values())} droppable.\n")
    L.append(f"Recommended: {rec['placed']} `placed`, {rec['blueprint']} `blueprint`. "
             f"Decided so far: {sum(dec.values())}"
             + (" (" + ", ".join(f"{v} {k}" for k, v in sorted(dec.items())) + ")"
                if dec else "") + ".\n")
    L.append("## How to decide\n")
    L.append("Set `decision` on a row in `tests/embedded_item_drift.json` to:\n")
    L.append("- `placed` — the placed copy is the real item: mint (or reuse an identical) "
             "blueprint from it and point the creature and all its placements at it. "
             "Every respawn then matches the first kill.\n"
             "- `blueprint` — the `.uti` is right: resync the placed copies to it. Only "
             "the first kill of the day changes.\n")
    L.append("Then `python3 bin/fix-embedded-item-drift.py` (dry run) and `--apply`. "
             "`--accept-recommended` applies the recommendation to every undecided row. "
             "Re-run this audit afterwards; resolved rows drop out.\n")
    L.append("The recommendation favours the **stronger** copy (NWN cost formula, "
             "`bin/loot_model.py` `CostModel`), overridden when the blueprint cannot be "
             "worn in that slot or a script tests only the placed tag (→ `placed`), and for "
             "cosmetic-only rows or ties (→ `blueprint`). With several placed variants the "
             "strongest is the candidate.\n")
    emb = [r for r in rows.values() if r["utc_form"] == "embedded"]
    L.append(f"**† Rows on split blueprints ({len(emb)}).** `bin/split-divergent-creatures.py` "
             "baked those creature blueprints from placements, so their `.utc` carries a "
             "**full item struct** instead of naming the item by resref. "
             f"{sum(r['utc_copy_is_placed'] for r in emb)} of them hold exactly the placed copy. "
             "Which copy the engine gives a respawn from such a struct — the struct itself, "
             "its `TemplateResRef`'s `.uti`, or nothing — has never been verified (hidden "
             "roadmap item `split-blueprint-embedded-items`). If it is the struct, those rows "
             "are not first-kill drift today, but they are still a blueprint that lies to "
             "the wiki. Either decision makes them unambiguous: the fixer rewrites the "
             "`.utc` entry in canonical resref form.\n")
    L.append("`tests/check_divergent_creatures.py` fails the repack on any drifting pair "
             "that is **not** in the decision file, or whose copies changed since it was "
             "recorded, so this list can only shrink.\n")
    titles = {"different-item": "Different item (the blueprint is another item entirely)",
              "stats": "Same base item, different properties",
              "identity": "Same stats, different tag/name",
              "cosmetic": "Cosmetic only"}
    for c in CLASS_ORDER:
        if not by[c]:
            continue
        L.append(f"## {titles[c]} — {len(by[c])}\n")
        if c == "cosmetic":
            L.append("Description, colour or model only: no effect on stats or loot value. "
                     "Most are blueprint descriptions rewritten by the 2026-08-24 local-LLM "
                     "description pass, which edited `.uti` files and not the copies "
                     "embedded in placements. Recommended `blueprint` (resync) unless noted "
                     "below; listed by item rather than one row per creature.\n")
            items = collections.defaultdict(list)
            for k, r in by[c]:
                items[r["item"]].append(r)
            L.append("| item | blueprint name | creatures | differs in | recommend |")
            L.append("|---|---|---|---|---|")
            for item, rs in sorted(items.items()):
                diff = sorted(set().union(*(r["differs"] for r in rs)))
                recs = collections.Counter(r["recommend"] for r in rs)
                rec = ", ".join(f"{n} {k}" for k, n in recs.most_common())
                L.append(f"| `{item}` | {rs[0]['blueprint_name'].replace('|', '/')} "
                         f"| {len(rs)} | {', '.join(diff)} | {rec} |")
            L.append("")
            continue
        L.append("| creature | item | where | drops | placed copy | blueprint | differs in "
                 "| recommend | decision |")
        L.append("|---|---|---|---|---|---|---|---|---|")
        for k, r in sorted(by[c], key=lambda kr: (kr[1]["creature_name"].lower(), kr[0])):
            where = ("inventory" if r["where"] == "inventory"
                     else SLOT_NAMES.get(int(r["where"].split(":")[1]), r["where"]))
            areas = ", ".join(r["areas"][:3]) + (" …" if len(r["areas"]) > 3 else "")
            var = f" ({r['variants']} variants)" if r["variants"] > 1 else ""
            if r["utc_form"] == "embedded":
                where += " †"
            esc = lambda s: str(s).replace("|", "\\|")  # noqa: E731
            L.append(
                f"| {esc(r['creature_name'])} `{r['creature']}` ×{r['placements']} ({areas}) "
                f"| `{r['item']}` | {where} | {'yes' if r['droppable'] else 'no'} "
                f"| {esc(r['placed_name'])}{var} · {fmt_value(r['placed_value'])} "
                f"| {esc(r['blueprint_name'])} · {fmt_value(r['blueprint_value'])} "
                f"| {', '.join(r['differs'])} "
                f"| **{r['recommend']}** — {esc(r['reason'])} | {r['decision'] or ''} |")
        L.append("")
    open(DOC, "w", encoding="utf-8").write("\n".join(L).rstrip() + "\n")


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--write", action="store_true",
                    help="rewrite tests/embedded_item_drift.json and the audit doc")
    args = ap.parse_args()

    rows = recommend(scan())
    old = load_decisions().get("pairs", {})
    for k, r in rows.items():
        o = old.get(k)
        if o and o.get("decision"):
            r["decision"] = o["decision"]
            if o.get("note"):
                r["note"] = o["note"]

    cls = collections.Counter(r["class"] for r in rows.values())
    rec = collections.Counter(r["recommend"] for r in rows.values())
    print(f"{len(rows)} drifting pairs on {len({r['creature'] for r in rows.values()})} "
          f"creature blueprints ({sum(r['placements'] for r in rows.values())} placed copies): "
          + ", ".join(f"{cls[c]} {c}" for c in CLASS_ORDER)
          + f"; recommend {rec['placed']} placed / {rec['blueprint']} blueprint")
    if args.write:
        doc = {
            "_comment": [
                "Embedded item drift: placed creature item copies that differ from their",
                ".uti. Generated by bin/audit-embedded-item-drift.py --write, which keeps",
                "every `decision` (and `note`) already filled in. Set decision to",
                "\"placed\" or \"blueprint\", then run bin/fix-embedded-item-drift.py.",
                "tests/check_divergent_creatures.py fails on any pair missing from here.",
            ],
            "pairs": rows,
        }
        # One pair per line: easy to edit a decision by hand, small diffs.
        body = ",\n".join(f"  {json.dumps(k, ensure_ascii=False)}: "
                          f"{json.dumps(v, ensure_ascii=False)}"
                          for k, v in sorted(rows.items()))
        with open(DECISIONS, "w", encoding="utf-8") as fh:
            fh.write("{\n \"_comment\": " + json.dumps(doc["_comment"], ensure_ascii=False)
                     + ",\n \"pairs\": {\n" + body + "\n }\n}\n")
        write_doc(rows)
        print(f"wrote {os.path.relpath(DECISIONS, ROOT)} and {os.path.relpath(DOC, ROOT)}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
