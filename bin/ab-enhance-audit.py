#!/usr/bin/env python3
"""ab-enhance-audit.py -- audit weapons carrying BOTH a generic Attack Bonus
and a generic Enhancement Bonus item property.

Background (roadmap defect ab-enhance-stack-bug): in NWN the Attack Bonus item
property (56) and the *attack component* of the Enhancement Bonus property (6)
do not stack -- only the higher applies to the to-hit roll -- while the
enhancement's damage + DR-bypass always apply. A weapon carrying both therefore
shows a confusing character sheet and (when AB <= ENH) wastes the AB property.

This script scans unpacked/*.uti.json and writes ab-enhance-audit.csv listing
every weapon with both a *generic* (Subtype 0) AB and ENH property. Edit that
CSV, then run bin/ab-enhance-apply.py to collapse each weapon to a single
property.

Columns:
  resref,name,base_item,enh_current,ab_current,relation,keep,value

  keep  -- which property to keep on apply: "attack" or "enhancement"
           (or "REVIEW" = unresolved; apply refuses to run while any remain)
  value -- the final +N for the kept property

Pre-fill rules:
  AB <= ENH  ->  keep=enhancement, value=enh_current  (AB is redundant; safe)
  AB >  ENH  ->  keep=REVIEW,      value=             (needs a human decision)
"""
import argparse
import csv
import glob
import json
import os
import sys

PROP_ENHANCEMENT = 6
PROP_ATTACK_BONUS = 56

REPO = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
UNPACKED = os.path.join(REPO, "unpacked")
OUT_CSV = os.path.join(REPO, "ab-enhance-audit.csv")


def resolved_name(d):
    loc = d.get("LocalizedName", {}).get("value")
    if isinstance(loc, dict) and loc:
        # English (lang id "0") if present, else first available string.
        return loc.get("0") or next(iter(loc.values()))
    return ""


def generic_value(props, prop_name):
    """Max CostValue across generic structs of prop_name, or None.

    Generic = the property's unused subtype, which NWN encodes as either 0 or
    65535 (0xFFFF, the empty-word sentinel). Matching only Subtype 0 silently
    skipped weapons whose AB/ENH carried 65535 (e.g. Chosen Kama).
    """
    vals = [
        p.get("CostValue", {}).get("value")
        for p in props
        if p.get("PropertyName", {}).get("value") == prop_name
        and p.get("Subtype", {}).get("value", 0) in (0, 65535)
        and p.get("CostValue", {}).get("value") is not None
    ]
    return max(vals) if vals else None


def main():
    ap = argparse.ArgumentParser(description=__doc__)
    ap.add_argument(
        "--force",
        action="store_true",
        help="overwrite ab-enhance-audit.csv even if it already exists "
        "(guards against clobbering hand-edited keep/value decisions)",
    )
    ap.add_argument(
        "--append",
        action="store_true",
        help="keep the existing ab-enhance-audit.csv rows verbatim (preserving "
        "hand-edited keep/value) and only add rows for resrefs not already "
        "listed. Use after fixing the subtype match to pick up newly-found "
        "weapons without re-deciding the historical ones.",
    )
    args = ap.parse_args()
    if args.force and args.append:
        print("--force and --append are mutually exclusive.", file=sys.stderr)
        return 1

    existing_rows = []
    existing_resrefs = set()
    if args.append:
        if not os.path.exists(OUT_CSV):
            print(f"--append needs an existing {OUT_CSV} -- run without it first.",
                  file=sys.stderr)
            return 1
        with open(OUT_CSV, newline="", encoding="utf-8") as fh:
            existing_rows = list(csv.DictReader(fh))
        existing_resrefs = {r["resref"] for r in existing_rows}
    elif os.path.exists(OUT_CSV) and not args.force:
        print(
            f"{OUT_CSV} already exists -- refusing to overwrite (your edits would\n"
            f"be lost). Re-run with --force to regenerate from scratch, or "
            f"--append to add only newly-found weapons.",
            file=sys.stderr,
        )
        return 1

    rows = []
    for path in glob.glob(os.path.join(UNPACKED, "*.uti.json")):
        try:
            d = json.load(open(path, encoding="utf-8"))
        except (ValueError, OSError):
            continue
        props = d.get("PropertiesList", {}).get("value", [])
        if not isinstance(props, list):
            continue
        ab = generic_value(props, PROP_ATTACK_BONUS)
        enh = generic_value(props, PROP_ENHANCEMENT)
        if ab is None or enh is None:
            continue
        resref = os.path.basename(path)[: -len(".uti.json")]
        if resref in existing_resrefs:
            continue  # --append: keep the existing (possibly hand-edited) row
        base_item = d.get("BaseItem", {}).get("value", "")
        if ab < enh:
            relation = "AB<ENH"
        elif ab > enh:
            relation = "AB>ENH"
        else:
            relation = "AB=ENH"
        if ab <= enh:
            keep, value = "enhancement", enh
        else:
            keep, value = "REVIEW", ""
        rows.append(
            {
                "resref": resref,
                "name": resolved_name(d),
                "base_item": base_item,
                "enh_current": enh,
                "ab_current": ab,
                "relation": relation,
                "keep": keep,
                "value": value,
            }
        )

    # REVIEW rows first (need attention), then by resref for stability.
    rows.sort(key=lambda r: (r["keep"] != "REVIEW", r["resref"]))

    fields = [
        "resref", "name", "base_item", "enh_current", "ab_current",
        "relation", "keep", "value",
    ]
    # In --append mode, existing rows are written back verbatim and the newly
    # found weapons are appended after them.
    out_rows = existing_rows + rows
    with open(OUT_CSV, "w", newline="", encoding="utf-8") as fh:
        w = csv.DictWriter(fh, fieldnames=fields)
        w.writeheader()
        w.writerows(out_rows)

    review = sum(1 for r in rows if r["keep"] == "REVIEW")
    if args.append:
        print(f"Updated {OUT_CSV} (kept {len(existing_rows)} existing row(s))")
        print(f"  {len(rows)} newly-found weapon(s) appended")
    else:
        print(f"Wrote {OUT_CSV}")
        print(f"  {len(rows)} weapons with both generic AB + ENH")
    print(f"  {review} flagged REVIEW (AB>ENH) -- edit keep/value before apply")
    print(f"  {len(rows) - review} pre-filled (AB<=ENH, drop redundant AB)")
    return 0


if __name__ == "__main__":
    sys.exit(main())
