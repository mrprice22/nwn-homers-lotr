#!/usr/bin/env python3
"""Build gate: no weapon carries both a generic Attack Bonus and a generic
Enhancement Bonus.

In NWN the Attack Bonus item property (56) and the *attack component* of the
Enhancement Bonus property (6) do not stack - only the higher applies to the
to-hit roll - while the enhancement's damage and damage-reduction bypass always
apply. A weapon carrying both therefore shows a confusing character sheet and,
whenever AB <= ENH, wastes the AB property outright. That is the
ab-enhance-stack-bug defect; bin/ab-enhance-audit.py + bin/ab-enhance-apply.py
were the one-shot cleanup, and this is the gate that keeps it clean.

It is also load-bearing for the shapeshift merge. ShapeMergeWeaponBonus in
unpacked/shape_merge_inc.nss resolves a shifted form's weapon down to a SINGLE
bonus, taking the better of the form weapon's own and the caster's. "The better
of the two" is only a well-defined question because a player-accessible weapon
never carries both at once - which was an assumption until this file existed
(tensors-transformation-not-merging-items-reliably, round 4).

Scope: every weapon base item, with no exemption for creature weapons. Creature
weapons DO legitimately want both at runtime - the engine ignores an enhancement
bonus for their attack and damage rolls but still honours it for DR bypass,
which is why ShapeCopyToCreatureWeapon builds exactly that pairing - but that is
a runtime effect on an engine-created claw, not a blueprint anyone edits. There
is deliberately no allowlist: fix the weapon, don't annotate the gate.

Generic = the property's unused subtype, which NWN encodes as either 0 or 65535
(0xFFFF, the empty-word sentinel). Matching only Subtype 0 silently skipped
weapons whose AB/ENH carried 65535 (e.g. Chosen Kama) - the same rule as
generic_value() in bin/ab-enhance-audit.py. The conditional variants (vs racial
group, vs alignment group, vs specific alignment) are separate property types
and are not this gate's business.
"""
import json
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
UNPACKED = ROOT / "unpacked"
BASEITEMS = ROOT / "hak_2da" / "baseitems.2da"

PROP_ENHANCEMENT = 6
PROP_ATTACK_BONUS = 56

# Fallback if baseitems.2da is unreadable: the stock weapon base item ids,
# including the four creature-weapon types (57-60) and the CEP/HotU additions.
FALLBACK_WEAPONS = set(range(0, 12)) | {
    12, 13, 14, 15, 16, 17, 18, 19, 20, 21, 22, 23, 24, 25, 26, 27, 28, 29, 30,
    31, 32, 33, 34, 40, 41, 42, 45, 47, 51, 54, 55, 56, 57, 58, 59, 60, 61, 62,
    63, 97, 98, 105, 108, 110, 111, 112,
}


def weapon_base_items():
    """Base item ids whose baseitems.2da WeaponType column is non-zero."""
    try:
        lines = BASEITEMS.read_text(encoding="latin-1").splitlines()
    except OSError:
        return FALLBACK_WEAPONS

    if len(lines) < 4:
        return FALLBACK_WEAPONS
    header = lines[2].split()
    try:
        col = header.index("WeaponType") + 1  # +1: cells[0] is the row index
    except ValueError:
        return FALLBACK_WEAPONS

    weapons = set()
    for ln in lines[3:]:
        cells = ln.split()
        if len(cells) <= col or not cells[0].isdigit():
            continue
        val = cells[col]
        if val.isdigit() and int(val) != 0:
            weapons.add(int(cells[0]))
    return weapons or FALLBACK_WEAPONS


def generic_value(props, prop_name):
    """Max CostValue across generic structs of prop_name, or None."""
    vals = [
        p.get("CostValue", {}).get("value")
        for p in props
        if p.get("PropertyName", {}).get("value") == prop_name
        and p.get("Subtype", {}).get("value", 0) in (0, 65535)
        and p.get("CostValue", {}).get("value") is not None
    ]
    return max(vals) if vals else None


def resolved_name(d):
    loc = d.get("LocalizedName", {}).get("value")
    if isinstance(loc, dict):
        # English (lang id "0") if present, else the first localized string.
        # A name that is only a TLK id ({"id": 90597}) has no text here.
        for key in ("0",) + tuple(k for k in loc if k != "id"):
            val = loc.get(key)
            if isinstance(val, str) and val:
                return val
    return ""


def main():
    weapons = weapon_base_items()
    offenders = []
    scanned = 0

    for path in sorted(UNPACKED.glob("*.uti.json")):
        try:
            d = json.loads(path.read_text(encoding="utf-8"))
        except (OSError, ValueError) as exc:
            print(f"check_ab_enhance: cannot read {path.name}: {exc}",
                  file=sys.stderr)
            return 1

        if d.get("BaseItem", {}).get("value") not in weapons:
            continue
        scanned += 1

        props = d.get("PropertiesList", {}).get("value", []) or []
        enh = generic_value(props, PROP_ENHANCEMENT)
        att = generic_value(props, PROP_ATTACK_BONUS)
        if enh is not None and att is not None:
            resref = path.name[: -len(".uti.json")]
            offenders.append((resref, resolved_name(d), enh, att))

    if offenders:
        print("check_ab_enhance: FAILED", file=sys.stderr)
        for resref, name, enh, att in offenders:
            print(f"  - {resref} ({name or 'unnamed'}): "
                  f"Enhancement +{enh} AND Attack Bonus +{att}", file=sys.stderr)
        print("", file=sys.stderr)
        print("  The two do not stack on the to-hit roll - only the higher "
              "applies - so one of them is dead weight and the character sheet "
              "reads wrong. Collapse each to a single property:", file=sys.stderr)
        print("    python3 bin/ab-enhance-audit.py --append   "
              "# adds rows, keeps existing decisions", file=sys.stderr)
        print("    # set keep=attack|enhancement and value on the new rows",
              file=sys.stderr)
        print("    python3 bin/ab-enhance-apply.py --apply    "
              "# rewrites blueprint AND every placed instance", file=sys.stderr)
        return 1

    print(f"check_ab_enhance: ok ({scanned} weapon blueprints, "
          f"{len(weapons)} weapon base items)")
    return 0


if __name__ == "__main__":
    sys.exit(main())
