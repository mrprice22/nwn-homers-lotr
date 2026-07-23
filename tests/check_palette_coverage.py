#!/usr/bin/env python3
"""Build gate: every blueprint must be filed in the toolset palette.

Blueprints that exist in unpacked/ but aren't listed as a RESREF leaf in the
matching `*palcus.itp.json` don't appear in the NWN toolset's palette tree at
all -- a DM can't find them to place. This gate fails the repack until every
blueprint of a gated type is filed, so orphans can't silently accumulate again.

Remedy when it fails: `python3 bin/file-palette-orphans.py --apply`
(files each orphan into its matching category, learned from existing members).

Reads unpacked/ + the palcus files directly -- no dependency on module-index/
(gitignored, may be absent on a fresh clone / in CI).
"""
import json
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
UNPACKED = ROOT / "unpacked"

# palcus stem -> (label, blueprint extension). Types that live in a palette.
PALETTES = {
    "itempalcus": ("item", "uti"),
    "creaturepalcus": ("creature", "utc"),
    "placeablepalcus": ("placeable", "utp"),
    "doorpalcus": ("door", "utd"),
    "encounterpalcus": ("encounter", "ute"),
    "storepalcus": ("store", "utm"),
    "triggerpalcus": ("trigger", "utt"),
    "waypointpalcus": ("waypoint", "utw"),
}


def palette_resrefs(stem: str) -> set[str]:
    """Every RESREF leaf anywhere in a palcus tree."""
    f = UNPACKED / f"{stem}.itp.json"
    if not f.exists():
        return set()
    found: set[str] = set()

    def walk(nodes):
        for n in nodes:
            rr = n.get("RESREF", {}).get("value")
            if rr:
                found.add(rr)
            child = n.get("LIST")
            if child and isinstance(child.get("value"), list):
                walk(child["value"])

    walk(json.loads(f.read_text()).get("MAIN", {}).get("value", []))
    return found


def main() -> int:
    problems = []
    total = 0
    for stem, (label, ext) in PALETTES.items():
        filed = palette_resrefs(stem)
        disk = {p.name[:-len(f".{ext}.json")]
                for p in UNPACKED.glob(f"*.{ext}.json")}
        total += len(disk)
        missing = sorted(disk - filed)
        if missing:
            problems.append((label, missing))

    if problems:
        n = sum(len(m) for _, m in problems)
        print(f"check_palette_coverage: {n} blueprint(s) not filed in the "
              f"toolset palette:")
        for label, missing in problems:
            shown = ", ".join(missing[:15])
            more = f" … (+{len(missing) - 15} more)" if len(missing) > 15 else ""
            print(f"  - {label}: {len(missing)} — {shown}{more}")
        print("  remedy: python3 bin/file-palette-orphans.py --apply")
        return 1

    print(f"check_palette_coverage: OK — {total} blueprints all filed in the "
          f"palette across {len(PALETTES)} palettes")
    return 0


if __name__ == "__main__":
    sys.exit(main())
