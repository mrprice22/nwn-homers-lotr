#!/usr/bin/env python3
"""One-off: mark every already-`awarded` idea as merit_awarded.

`merit_awarded` is the flag that says the merit for an idea was really paid
into meritdb. It was added when the roadmap editor grew Award / Revoke buttons;
before that, `status: awarded` was the only record, and every one of those was
paid by hand in-game. So the whole existing `awarded` set is back-populated to
merit_awarded: true — otherwise the first time one of them passed through the
Award button it would pay the submitter a second time.

Idempotent: re-running changes nothing. Dry-run by default; --apply writes.
Writes through the editor's own write_document(), so comments and every block
other than `ideas:` come out byte-identical.

    python3 bin/backfill-merit-awarded.py            # show what would change
    python3 bin/backfill-merit-awarded.py --apply
"""
from __future__ import annotations

import argparse
import importlib.util
import sys
from pathlib import Path

REPO = Path(__file__).resolve().parent.parent
EDITOR = REPO / "bin" / "roadmap-editor.py"


def load_editor():
    """Import roadmap-editor.py (hyphenated name) for read/write_document."""
    spec = importlib.util.spec_from_file_location("roadmap_editor", EDITOR)
    mod = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(mod)
    return mod


def main() -> int:
    ap = argparse.ArgumentParser(description=__doc__,
                                 formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--apply", action="store_true",
                    help="write roadmap.yaml (default: dry run)")
    args = ap.parse_args()

    ed = load_editor()
    data = ed.read_yaml()
    ideas = data.get("ideas", []) or []
    flag = ed.MERIT_FLAG

    todo = [i for i in ideas
            if i.get("status") == "awarded" and not i.get(flag)]
    for idea in todo:
        print(f"  {idea.get('id')}  ({idea.get('type') or 'no type'}, "
              f"{idea.get('player') or 'no submitter'})")
    print(f"{len(todo)} awarded idea(s) to flag; "
          f"{sum(1 for i in ideas if i.get(flag))} already flagged.")
    if not todo:
        return 0
    if not args.apply:
        print("Dry run — re-run with --apply to write roadmap.yaml.")
        return 0

    for idea in todo:
        idea[flag] = True
    errors = ed.validate_internal_fields(ideas)
    if errors:
        print("Refusing to write — validation errors:", file=sys.stderr)
        for e in errors:
            print(f"  • {e}", file=sys.stderr)
        return 1
    ed.write_document(ideas)
    print(f"Wrote {ed.YAML_PATH}.")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
