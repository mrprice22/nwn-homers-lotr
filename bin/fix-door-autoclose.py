#!/usr/bin/env python3
"""Wire auto-close onto every placed area-transition door that lacks it.

NWScript has no module-level door hook, so this module closes doors with a
per-instance OnOpen one-liner (unpacked/close_door.nss and friends). Most placed
doors never got one: at the time this script was written, 335 of the 414
area-transition doors had an empty OnOpen, which is the "doors stay open behind
you" defect players report.

What it touches
---------------
Only doors that are BOTH an area transition (LinkedTo set) and unscripted
(OnOpen empty). That makes it idempotent - a second run is a no-op - and keeps
it off the ~300 interior/decorative doors, which are out of scope.

Which script it assigns
-----------------------
    close_door_lock   the door is Locked/KeyRequired, has a KeyName, and does
                      NOT consume that key (AutoRemoveKey != 1) -> closing and
                      re-locking is safe, the player can always get back in.
    close_door        everything else, including:
                        * key-CONSUMING doors (AutoRemoveKey == 1) - re-locking
                          strands the player behind a lock whose key is gone;
                        * keyless locked doors (pick-or-bash only) - re-locking
                          forces a fresh pick on every pass and can shut a
                          rogue-less party inside a dungeon.

Doors a quest script forces open are exempt: re-closing them would undo a lever
or a plot event. EXEMPT_TAGS is discovered by scanning the module's own scripts,
plus EXTRA_EXEMPT_TAGS below for anything the scan cannot see.

Dry-run by default; pass --apply to write. This is NOT a wiki refresh.
"""

import argparse
import glob
import json
import os
import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
UNPACKED = ROOT / "unpacked"

CLOSE_PLAIN = "close_door"
CLOSE_RELOCK = "close_door_lock"

# A .nss that forces a door open: the doors it names must never auto-close.
FORCE_OPEN_RE = re.compile(r"ActionOpenDoor|SetLocked\s*\([^,]+,\s*FALSE")
TAG_RE = re.compile(r"Get(?:Nearest)?ObjectByTag\s*\(\s*\"([^\"]+)\"")

# Doors deliberately left open that the script scan cannot discover (a door
# opened via a local variable, a tag built at runtime, a plot door held open by
# design). Add here with a reason; tests/check_door_autoclose.py honours it too.
EXTRA_EXEMPT_TAGS = set()


# --------------------------------------------------------------------------- #
# helpers
# --------------------------------------------------------------------------- #
def v(node, default=""):
    """Value of a GFF-as-JSON typed node."""
    return node.get("value", default) if isinstance(node, dict) else default


def load(path):
    return json.loads(Path(path).read_text(encoding="utf-8"))


def dump(path, data, style):
    """Write back in the file's own formatting.

    The tree is NOT uniform: nwn_gff emits indent=1 with no trailing newline,
    but files a previous tool rewrote are indent=2 with one. Guessing wrong
    reformats every line and buries the one-field change in a 25,000-line diff,
    so the style is measured per file before editing (see read_style).
    """
    indent, trailing_nl = style
    text = json.dumps(data, indent=indent, ensure_ascii=False)
    Path(path).write_text(text + ("\n" if trailing_nl else ""), encoding="utf-8")


def read_style(path):
    """(indent, trailing_newline) as the file is currently written."""
    text = Path(path).read_text(encoding="utf-8")
    indent = 1
    for line in text.split("\n")[1:]:
        stripped = line.lstrip(" ")
        if stripped:
            indent = len(line) - len(stripped)
            break
    return (indent or 1, text.endswith("\n"))


def exempt_tags():
    """Door tags that a module script forces open."""
    tags = set(EXTRA_EXEMPT_TAGS)
    for nss in glob.glob(str(UNPACKED / "*.nss")):
        src = Path(nss).read_text(encoding="utf-8", errors="ignore")
        if FORCE_OPEN_RE.search(src):
            tags.update(TAG_RE.findall(src))
    return tags


def chosen_script(door):
    """Which auto-close script this door should get, or None to skip."""
    locked = v(door.get("Locked"), 0) or v(door.get("KeyRequired"), 0)
    if not locked:
        return CLOSE_PLAIN
    key = v(door.get("KeyName"), "")
    consumes_key = v(door.get("AutoRemoveKey"), 0) == 1
    if key and not consumes_key:
        return CLOSE_RELOCK
    # No key at all (pick/bash only), or the key is eaten on first use.
    return CLOSE_PLAIN


def scan():
    """Every unscripted transition door, as (area, index, door, script)."""
    exempt = exempt_tags()
    todo, skipped = [], []
    for path in sorted(glob.glob(str(UNPACKED / "*.git.json"))):
        area = os.path.basename(path)[: -len(".git.json")]
        data = load(path)
        for i, door in enumerate(data.get("Door List", {}).get("value", [])):
            if not v(door.get("LinkedTo")):
                continue                       # interior/decorative, out of scope
            if v(door.get("OnOpen")):
                continue                       # already wired
            tag = v(door.get("Tag"))
            if tag in exempt:
                skipped.append((area, i, tag))
                continue
            todo.append((area, path, i, door, chosen_script(door)))
    return todo, skipped, exempt


# --------------------------------------------------------------------------- #
# main
# --------------------------------------------------------------------------- #
def main():
    ap = argparse.ArgumentParser(
        description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--apply", action="store_true",
                    help="write the changes (default: report only)")
    ap.add_argument("--verbose", action="store_true",
                    help="list every door, not just the locked ones")
    args = ap.parse_args()

    todo, skipped, exempt = scan()

    if not todo:
        print("All placed area-transition doors already auto-close. Nothing to do.")
        return 0

    # The locked doors are the judgement calls - always show those in full.
    locked = [t for t in todo
              if v(t[3].get("Locked"), 0) or v(t[3].get("KeyRequired"), 0)]
    if locked:
        print("Locked / key-required doors (the re-lock decision):")
        print(f"  {'area':<20}{'tag':<24}{'key':<16}{'eats key':<10}script")
        for area, _path, _i, door, script in locked:
            print(f"  {area:<20}{v(door.get('Tag')):<24}"
                  f"{v(door.get('KeyName')) or '-':<16}"
                  f"{('YES' if v(door.get('AutoRemoveKey'), 0) == 1 else 'no'):<10}"
                  f"{script}")
        print()

    if args.verbose:
        print("All doors to be wired:")
        for area, _path, i, door, script in todo:
            print(f"  {area:<20}#{i:<4}{v(door.get('Tag')):<24}"
                  f"-> {v(door.get('LinkedTo')):<24}{script}")
        print()

    plain = sum(1 for t in todo if t[4] == CLOSE_PLAIN)
    relock = sum(1 for t in todo if t[4] == CLOSE_RELOCK)
    areas = len({t[0] for t in todo})
    print(f"{len(todo)} unscripted transition doors in {areas} areas: "
          f"{plain} {CLOSE_PLAIN}, {relock} {CLOSE_RELOCK}")
    print(f"{len(skipped)} exempt (forced open by a script), "
          f"{len(exempt)} exempt tags known")
    for area, i, tag in skipped:
        print(f"  exempt: {area} #{i} {tag}")

    if not args.apply:
        print("\nDry run. Re-run with --apply to write.")
        return 0

    # Group by file so each area is read and written once.
    by_file = {}
    for _area, path, i, _door, script in todo:
        by_file.setdefault(path, []).append((i, script))

    for path, edits in by_file.items():
        style = read_style(path)
        data = load(path)
        doors = data["Door List"]["value"]
        for i, script in edits:
            doors[i]["OnOpen"]["value"] = script
        dump(path, data, style)

    print(f"\nWrote {len(by_file)} area files.")
    return 0


if __name__ == "__main__":
    sys.exit(main())
