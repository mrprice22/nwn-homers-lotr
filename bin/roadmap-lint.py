#!/usr/bin/env python3
"""Validate roadmap.yaml with the *exact* checks the roadmap editor runs on save.

Run this after any edit to roadmap.yaml — by hand, by an agent, by autopilot.
A clean run means the editor service will accept the file; a failing run means
the admin cannot save anything in the GUI (validation is whole-file, so one bad
item blocks adding a brand-new idea).

There is deliberately **no second copy of the rules here**: this imports
bin/roadmap-editor.py and calls its `validate_document()`, the same function the
service's save handler calls. If the rules change, both move together.

    python3 bin/roadmap-lint.py          # validate, exit 1 on any error
    python3 bin/roadmap-lint.py -q       # errors only, no OK line

Common failure and its fix:
  "status 'implemented' with N unfinished blocker manual_step(s)"
      A shipped item still has blocking admin work. Either finish the step
      (status: done) or move the item to `status: manual`. A UAT check is never
      a blocker — see CLAUDE-roadmap.md.
"""
import argparse
import importlib.util
import sys
from pathlib import Path

REPO = Path(__file__).resolve().parent.parent
EDITOR_PATH = REPO / "bin" / "roadmap-editor.py"


def load_editor():
    """Import bin/roadmap-editor.py (hyphenated name) for its validators."""
    spec = importlib.util.spec_from_file_location("roadmap_editor", EDITOR_PATH)
    mod = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(mod)
    return mod


def main() -> int:
    ap = argparse.ArgumentParser(description=__doc__,
                                 formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("-q", "--quiet", action="store_true",
                    help="print nothing when the file is valid")
    ap.add_argument("--warnings", action="store_true",
                    help="also print advisory warnings (duplicate-idea hints)")
    args = ap.parse_args()

    ED = load_editor()
    data = ED.read_yaml()
    errors, warnings = ED.validate_document(
        data.get("ideas") or [],
        data.get("groups") or [],
        data.get("players") or [],
        data.get("epics") or [],
    )

    if args.warnings:
        for w in warnings:
            print(f"  [warn] {w}", file=sys.stderr)
    if errors:
        print(f"roadmap.yaml has {len(errors)} error(s) — the editor will refuse "
              f"to save until they are fixed:", file=sys.stderr)
        for e in errors:
            print(f"  [error] {e}", file=sys.stderr)
        return 1
    if not args.quiet:
        print(f"roadmap.yaml OK ({len(data.get('ideas') or [])} ideas)")
    return 0


if __name__ == "__main__":
    sys.exit(main())
