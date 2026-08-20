#!/usr/bin/env python3
"""Map-note coverage check (build-time smoke test).

Every area transition should carry a map-note pin on the area map telling the
player where it goes. That was a live player report: Weathertop and its
neighbours had no pins at all, so nine crossings - three in each direction
between Weather Hills and Weathertop, plus the wolf cave - were unlabelled and
the player had no way to tell from the map where any of them led.

The invariant this enforces:

    every door / trigger / placeable transition the area graph knows about must
    have a map note, unless the builder marked it @nomapnote.

Both halves of that come straight from bin/gen-map-notes.py - this gate imports
its scan() rather than re-deriving anything, so a transition the tool exempts is
automatically a transition this gate stops asking about (same arrangement as
tests/check_door_autoclose.py and bin/fix-door-autoclose.py).

Deliberately NOT failures:

  * a transition whose source object no longer exists in the area, or whose tag
    serves several destinations at once (the Gwathdor maze) - there is nothing
    the tool could place, so blocking the build would be a dead end;
  * a broken LinkedTo that leads nowhere - real, reported by the tool, but a
    content bug rather than a missing pin.

Exits 0 if every transition is labelled, 1 otherwise (prints offenders and the
exact command that fixes them).

Two conditions make this gate stand down rather than block, both because
module-index/area_graph.json is a gitignored WIKI artefact this tool may not
rebuild:

  * the graph is missing (fresh clone, wiki never run) - skip;
  * the graph predates an area that exists in unpacked/ - warn, because a
    builder who adds an area and repacks before the daily refresh has a graph
    that cannot yet see it.
"""

import importlib.util
import os
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
TOOL = os.path.join(ROOT, "bin", "gen-map-notes.py")
FIX = "python3 bin/gen-map-notes.py --apply"


def load_tool():
    """Import bin/gen-map-notes.py (hyphens make it non-importable by name)."""
    spec = importlib.util.spec_from_file_location("gen_map_notes", TOOL)
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


def main():
    if not os.path.exists(TOOL):
        print(f"FAIL: {TOOL} is missing - the map-note gate cannot run "
              f"without it.")
        return 1

    tool = load_tool()

    if not tool.GRAPH.exists():
        print(f"SKIP: {tool.GRAPH.relative_to(tool.ROOT)} not built yet "
              f"(run the wiki once to populate module-index/).")
        return 0

    res = tool.scan()
    unseen = tool.graph_is_stale()

    if not res.uncovered:
        covered = (res.stats["unchanged"] + res.stats["updated"]
                   + res.stats["dup-skip"] + res.stats["manual-skip"]
                   + res.stats["manual-fix"] + res.stats["manual-mismatch"])
        note = f", {res.stats['exempt']} exempt via @nomapnote" \
            if res.stats["exempt"] else ""
        print(f"OK: every area transition carries a map note "
              f"({covered} pinned{note}).")
        if unseen:
            print(f"     warning: area_graph.json predates {len(unseen)} "
                  f"area(s) - their transitions are not checked "
                  f"({', '.join(unseen[:5])}).")
        return 0

    if unseen:
        print(f"WARN: {len(res.uncovered)} unlabelled transition(s), but "
              f"area_graph.json predates {len(unseen)} area(s) in unpacked/ - "
              f"the graph does not match the tree, so this is not being "
              f"treated as a failure.")
        print(f"      refresh the wiki, then: {FIX}")
        return 0

    print(f"FAIL: {len(res.uncovered)} area transition(s) have no map note - "
          f"players cannot tell from the map where they lead:\n")
    print(f"  {'area':<22}{'kind':<9}{'object tag':<26}-> destination")
    for area, kind, label, dest in res.uncovered:
        print(f"  {area:<22}{kind:<9}{label:<26}-> {dest}")
    print(f"\nfix: {FIX}")
    print("     or mark the transition deliberately unlabelled by putting "
          "@nomapnote")
    print("     in the object's Comment box in the toolset.")
    return 1


if __name__ == "__main__":
    sys.exit(main())
