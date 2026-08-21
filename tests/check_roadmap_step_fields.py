#!/usr/bin/env python3
"""Build gate: the roadmap editor's hand-off panel must round-trip every
manual_step field the serializer can write.

The panel is not a form over the stored step - it holds its own copy (`HO`) and
rewrites the WHOLE `manual_steps` list on every save. So a key it fails to carry
is not merely ignored: it is deleted, silently, from every step of every idea
the admin opens.

That shipped, and ran for months. `initHandoff()`/`handoffOut()` modelled only
{step, status, blocker, step_h}, so each save re-stamped `kind: admin` (the
default normalize_step() supplies) and dropped `tester` outright - destroying
~393 `kind` and ~175 `tester` values across 17 commits. The damage is invisible
in the editor and only shows up two surfaces away: per bin/gen-roadmap.py's
open_uat_steps(), a step demoted to `admin` drops out of the UAT and Toolset
queues AND out of the "shipped but not validated" predicate the wiki page and
the in-game Recent Updates sign share.

The check: every key normalize_step() can emit must appear in the page's
HO_OWNED list, and every key the panel claims to own must be one the serializer
recognises. Adding a field to normalize_step() without teaching the panel about
it fails the repack instead of quietly eating data.

Exit 0 = clean, 1 = the panel would drop a field on save.
"""
from __future__ import annotations

import re
import sys
from pathlib import Path

REPO = Path(__file__).resolve().parent.parent
EDITOR = REPO / "bin" / "roadmap-editor.py"

# Every optional key normalize_step() can put on a step, alongside the ones it
# always writes. Kept explicit rather than probed so that a new field has to be
# named in two places on purpose.
PROBE = {
    "step": "a step",
    "status": "done",
    "kind": "uat",
    "blocker": True,
    "tester": "wizard 43+",
    "step_h": 96,
}


def load_editor():
    """Import bin/roadmap-editor.py without running its server."""
    import importlib.util

    spec = importlib.util.spec_from_file_location("roadmap_editor", EDITOR)
    mod = importlib.util.module_from_spec(spec)
    sys.modules["roadmap_editor"] = mod
    spec.loader.exec_module(mod)
    return mod


def page_ho_owned(mod) -> set[str]:
    """The HO_OWNED list as the browser sees it, read out of the page source."""
    m = re.search(r"const HO_OWNED = \[([^\]]*)\]", mod.PAGE)
    if not m:
        raise SystemExit("check_roadmap_step_fields: no HO_OWNED array in PAGE "
                         "- did the hand-off panel get restructured?")
    return set(re.findall(r"'([^']+)'", m.group(1)))


def main() -> int:
    mod = load_editor()
    owned = page_ho_owned(mod)
    emitted = set(mod.normalize_step(dict(PROBE)))

    problems: list[str] = []
    missing = sorted(emitted - owned)
    if missing:
        problems.append(
            "the hand-off panel does not carry these manual_step fields, so a "
            "GUI save DELETES them: " + ", ".join(missing)
            + "\n  fix: add them to HO_OWNED, initHandoff() and handoffOut() in "
              "bin/roadmap-editor.py")
    stray = sorted(owned - emitted)
    if stray:
        problems.append(
            "the hand-off panel claims to own fields normalize_step() never "
            "emits: " + ", ".join(stray)
            + "\n  fix: drop them from HO_OWNED, or teach normalize_step() "
              "about them")

    # The panel's default textarea height must be reachable. The CSS floors a
    # textarea at min-height, so a smaller HO_DEFAULT_H can never equal the
    # measured offsetHeight - and syncHandoffHeights() then stamps a spurious
    # `step_h` on every sub-item of every idea it saves.
    d = re.search(r"const HO_DEFAULT_H = (\d+)", mod.PAGE)
    floor = re.search(r"textarea \{ min-height:(\d+)px", mod.PAGE)
    if d and floor and int(d.group(1)) < int(floor.group(1)):
        problems.append(
            f"HO_DEFAULT_H is {d.group(1)}px but the CSS floors a textarea at "
            f"{floor.group(1)}px, so it is unreachable and every save will "
            f"write a spurious *_h on every question and step"
            f"\n  fix: raise HO_DEFAULT_H to the min-height")

    if problems:
        print("FAIL: roadmap editor hand-off panel field coverage")
        for p in problems:
            print("  - " + p)
        return 1
    print(f"ok: hand-off panel round-trips all {len(emitted)} manual_step "
          f"fields ({', '.join(sorted(emitted))})")
    return 0


if __name__ == "__main__":
    sys.exit(main())
