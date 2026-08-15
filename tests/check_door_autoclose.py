#!/usr/bin/env python3
"""Door auto-close coverage check (build-time smoke test).

Doors in this module close themselves through a per-instance OnOpen script
(unpacked/close_door.nss and close_door_lock.nss) - NWScript has no module-level
door hook, so a door with an empty OnOpen simply stays open forever once a player
opens it. That was a live player report: the door out of a player home, the
Appearance Changer door and Tagget's Smith all standing open behind you.

The invariant this enforces:

    every PLACED door that is an area transition (LinkedTo set) must have a
    non-empty OnOpen, unless its tag is exempt because a quest script forces it
    open on purpose.

Interior/decorative doors (no LinkedTo) are deliberately out of scope - they are
cosmetic and closing them mid-fight would be a behaviour change nobody asked for.

The exemption set and the "which close script does this door deserve" rule both
live in bin/fix-door-autoclose.py, which is also the tool that fixes offenders.
Importing them from there keeps one source of truth: adding an exemption to the
fixer automatically teaches this gate about it.

Exits 0 if every transition door auto-closes, 1 otherwise (prints offenders and
the exact command that fixes them).
"""

import importlib.util
import os
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
FIXER = os.path.join(ROOT, "bin", "fix-door-autoclose.py")


def load_fixer():
    """Import bin/fix-door-autoclose.py (hyphens make it non-importable by name)."""
    spec = importlib.util.spec_from_file_location("fix_door_autoclose", FIXER)
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


def main():
    if not os.path.exists(FIXER):
        print(f"FAIL: {FIXER} is missing - the door gate cannot run without it.")
        return 1

    fixer = load_fixer()
    todo, skipped, _exempt = fixer.scan()

    if not todo:
        count = len(skipped)
        print(f"OK: every placed area-transition door auto-closes "
              f"({count} exempt by script).")
        return 0

    print(f"FAIL: {len(todo)} placed area-transition door(s) have no OnOpen and "
          f"will stay open forever once a player opens them:\n")
    print(f"  {'area':<20}{'#':<5}{'tag':<24}{'-> linked to':<26}needs")
    for area, _path, i, door, script in todo:
        tag = fixer.v(door.get("Tag")) or "(untagged)"
        dest = fixer.v(door.get("LinkedTo"))
        print(f"  {area:<20}{i:<5}{tag:<24}{dest:<26}{script}")

    print("\nFix with:  python3 bin/fix-door-autoclose.py --apply")
    print("If a door is MEANT to stay open (a lever or plot event opens it), add "
          "its tag to EXTRA_EXEMPT_TAGS in bin/fix-door-autoclose.py with a reason.")
    return 1


if __name__ == "__main__":
    sys.exit(main())
