#!/usr/bin/env python3
"""Generate clean Cost=0 "blank" item blueprints, one per base item type used in
the module, for the forge's enchantment-value calculation.

Why: NWN's GetGoldPieceValue returns an item's fixed blueprint Cost override (when
set) and ignores its actual properties — so stripping enchantments off such an item
(e.g. The High Staff, Cost 2,426,048) never lowers its assessed worth. To price an
item by its *enchantments*, the forge rebuilds it on a base that has NO Cost
override and lets the engine compute the value (forge_inc.nss ForgeRebuildValue).
That rebuild needs a createable, property-free, Cost=0 blueprint of the right base
item type: these blanks.

Each blank is derived from a real module item of the same BaseItem (so the model
parts / structure are valid and instantiable via CreateItemOnObject) but stripped
to nothing: no properties, Cost/AddCost/Charges 0, generic name, resref/tag
`forge_blank_<baseitem>`.

Idempotent: regenerates unpacked/forge_blank_*.uti.json from the current item set.
Run from anywhere; writes into <repo>/unpacked.
"""

import json
from pathlib import Path

UNPACKED = Path(__file__).resolve().parent.parent / "unpacked"
PREFIX = "forge_blank_"


def loc(s):
    return {"type": "cexolocstring", "value": {"0": s}}


def main():
    # Pick one representative source item per base item type. Prefer items that
    # already have zero properties (cleanest structure), else any item of the type.
    by_base = {}      # baseitem -> (n_props, filename)
    for f in sorted(UNPACKED.glob("*.uti.json")):
        if f.name.startswith(PREFIX):
            continue
        try:
            d = json.loads(f.read_text())
        except Exception:
            continue
        bi = d.get("BaseItem", {}).get("value")
        if bi is None:
            continue
        nprop = len(d.get("PropertiesList", {}).get("value", []))
        cur = by_base.get(bi)
        if cur is None or nprop < cur[0]:
            by_base[bi] = (nprop, f)

    written = 0
    for bi, (_, src) in sorted(by_base.items()):
        d = json.loads(src.read_text())
        resref = f"{PREFIX}{bi}"
        if len(resref) > 16:
            print(f"  skip base {bi}: resref '{resref}' >16 chars")
            continue
        # Strip to a clean, valueless, property-free blank of this base type;
        # keep the model parts (BaseItem + ModelPart*/appearance fields) so the
        # item is valid and instantiable.
        d["PropertiesList"] = {"type": "list", "value": []}
        d["Cost"] = {"type": "dword", "value": 0}
        d["AddCost"] = {"type": "dword", "value": 0}
        if "Charges" in d:
            d["Charges"] = {"type": "byte", "value": 0}
        d["StackSize"] = {"type": "word", "value": 1}
        d["Plot"] = {"type": "byte", "value": 0}
        d["Cursed"] = {"type": "byte", "value": 0}
        d["Stolen"] = {"type": "byte", "value": 0}
        d["Identified"] = {"type": "byte", "value": 1}
        d["TemplateResRef"] = {"type": "resref", "value": resref}
        d["Tag"] = {"type": "cexostring", "value": resref}
        d["Comment"] = {"type": "cexostring", "value":
                        "Auto-generated forge valuation blank — do not edit."}
        d["LocalizedName"] = loc("Forge Blank")
        d["Description"] = loc("")
        d["DescIdentified"] = loc("")
        out = UNPACKED / f"{resref}.uti.json"
        out.write_text(json.dumps(d, indent=2, ensure_ascii=False) + "\n")
        written += 1

    print(f"gen-forge-blanks: wrote {written} blank blueprint(s) for base types "
          f"{sorted(by_base)}")


if __name__ == "__main__":
    main()
