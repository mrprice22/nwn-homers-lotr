#!/usr/bin/env python3
"""ab-enhance-apply.py -- apply ab-enhance-audit.csv to weapon blueprints AND to
every embedded item instance already placed in the module.

Reads ab-enhance-audit.csv (produced/edited from bin/ab-enhance-audit.py) and,
for each listed weapon resref, collapses the conflicting generic (Subtype 0)
Attack Bonus (56) + Enhancement Bonus (6) properties down to a single property:

  keep=enhancement -> remove generic AB(56); set generic ENH(6) to `value`.
  keep=attack      -> remove generic ENH(6); set generic AB(56)  to `value`.

It rewrites:
  * the item blueprint            unpacked/<resref>.uti.json
  * every embedded instance whose TemplateResRef matches a resref, found by
    recursively walking ALL GFF files that can carry items:
      .git.json (placed creatures/containers/ground items),
      .utc.json (creature blueprint inventories/equip),
      .utm.json (store inventories), .utp.json (placeable inventories),
      .uti.json (the blueprint's own top-level item).

Conditional variants (AB/ENH vs Race / vs Alignment, Subtype != 0) and all other
properties are left untouched. Refuses to run while any row is unresolved
(keep != attack|enhancement, or a non-integer value). Idempotent: a second run
makes no changes.

Robustness note: spreadsheet editors strip leading zeros from numeric resrefs
(015 -> 15). resolve_resref() maps a CSV resref back to the real blueprint file
(exact match, else the unique zero-padded numeric file).
"""
import csv
import glob
import json
import os
import sys

PROP_ENHANCEMENT = 6
PROP_ATTACK_BONUS = 56
COST_TABLE = 2  # the +N value table used by both generic AB and ENH

REPO = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
UNPACKED = os.path.join(REPO, "unpacked")
IN_CSV = os.path.join(REPO, "ab-enhance-audit.csv")
ITEM_EXTS = ("uti", "git", "utc", "utm", "utp")

KEEP_TO_PROP = {"enhancement": PROP_ENHANCEMENT, "attack": PROP_ATTACK_BONUS}


def make_prop(prop_name, value):
    """A generic, unconditional item-property struct at the given +N value."""
    return {
        "__struct_id": 0,
        "ChanceAppear": {"type": "byte", "value": 100},
        "CostTable": {"type": "byte", "value": COST_TABLE},
        "CostValue": {"type": "word", "value": value},
        "Param1": {"type": "byte", "value": 255},
        "Param1Value": {"type": "byte", "value": 0},
        "PropertyName": {"type": "word", "value": prop_name},
        "Subtype": {"type": "word", "value": 0},
    }


def is_generic(p, prop_name):
    """True for a generic (Subtype 0) struct of the given property."""
    return (
        isinstance(p, dict)
        and p.get("PropertyName", {}).get("value") == prop_name
        and p.get("Subtype", {}).get("value", 0) == 0
    )


def transform(item, keep_prop, value):
    """Collapse generic AB/ENH on one item struct in place. Return True if changed."""
    pl = item.get("PropertiesList")
    if not isinstance(pl, dict) or not isinstance(pl.get("value"), list):
        return False
    props = pl["value"]
    drop_prop = PROP_ATTACK_BONUS if keep_prop == PROP_ENHANCEMENT else PROP_ENHANCEMENT
    new_props = [p for p in props if not is_generic(p, drop_prop)]
    if any(is_generic(p, keep_prop) for p in new_props):
        for p in new_props:
            if is_generic(p, keep_prop):
                p["CostValue"]["value"] = value
    else:
        new_props.append(make_prop(keep_prop, value))
    if new_props != props:
        pl["value"] = new_props
        return True
    return False


def walk_items(o):
    """Yield every embedded item node (dict with TemplateResRef + PropertiesList)."""
    if isinstance(o, dict):
        if "TemplateResRef" in o and "PropertiesList" in o:
            yield o
        for v in o.values():
            yield from walk_items(v)
    elif isinstance(o, list):
        for v in o:
            yield from walk_items(v)


def resolve_resref(csv_resref):
    """Map a CSV resref to the real blueprint resref (handles stripped zeros)."""
    if os.path.exists(os.path.join(UNPACKED, csv_resref + ".uti.json")):
        return csv_resref
    if csv_resref.isdigit():
        cands = [
            os.path.basename(p)[: -len(".uti.json")]
            for p in glob.glob(os.path.join(UNPACKED, "*.uti.json"))
            if os.path.basename(p)[: -len(".uti.json")].isdigit()
            and int(os.path.basename(p)[: -len(".uti.json")]) == int(csv_resref)
        ]
        if len(cands) == 1:
            return cands[0]
    return None


def main():
    if not os.path.exists(IN_CSV):
        print(f"missing {IN_CSV} -- run bin/ab-enhance-audit.py first", file=sys.stderr)
        return 1

    rows = list(csv.DictReader(open(IN_CSV, encoding="utf-8")))

    # Validate every row and resolve resrefs before touching any file.
    errors = []
    plan = {}  # canonical resref -> (keep_prop, value)
    for r in rows:
        keep = (r.get("keep") or "").strip().lower()
        val = (r.get("value") or "").strip().lstrip("+")
        if keep not in KEEP_TO_PROP:
            errors.append(f"  {r['resref']}: keep={r.get('keep')!r} (need attack|enhancement)")
            continue
        if not val.isdigit():
            errors.append(f"  {r['resref']}: value={r.get('value')!r} (need an integer)")
            continue
        canon = resolve_resref(r["resref"])
        if canon is None:
            errors.append(f"  {r['resref']}: no matching unpacked/*.uti.json blueprint")
            continue
        plan[canon] = (KEEP_TO_PROP[keep], int(val))
    if errors:
        print("Refusing to run -- unresolved rows:", file=sys.stderr)
        print("\n".join(errors), file=sys.stderr)
        return 1

    bp_changed = 0
    inst_changed = 0
    inst_files = 0

    # 1) Blueprints, by filename (authoritative even if TemplateResRef differs).
    for resref, (keep_prop, value) in plan.items():
        path = os.path.join(UNPACKED, resref + ".uti.json")
        orig = open(path, encoding="utf-8").read()
        d = json.loads(orig)
        transform(d, keep_prop, value)
        new = json.dumps(d, indent=2, ensure_ascii=False) + "\n"
        if new != orig:
            open(path, "w", encoding="utf-8").write(new)
            bp_changed += 1

    # 2) Embedded instances, by TemplateResRef, across every item-bearing GFF.
    for ext in ITEM_EXTS:
        for path in glob.glob(os.path.join(UNPACKED, f"*.{ext}.json")):
            orig = open(path, encoding="utf-8").read()
            d = json.loads(orig)
            n = 0
            for item in walk_items(d):
                trr = item.get("TemplateResRef", {})
                trr = trr.get("value") if isinstance(trr, dict) else None
                if trr in plan:
                    keep_prop, value = plan[trr]
                    if transform(item, keep_prop, value):
                        n += 1
            if n:
                new = json.dumps(d, indent=2, ensure_ascii=False) + "\n"
                if new != orig:
                    open(path, "w", encoding="utf-8").write(new)
                    inst_changed += n
                    inst_files += 1

    print(f"Resolved {len(plan)} weapon resrefs.")
    print(f"  blueprints changed : {bp_changed}")
    print(f"  instances changed  : {inst_changed} across {inst_files} file(s)")
    return 0


if __name__ == "__main__":
    sys.exit(main())
