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


# Shipped statuses, and the day the `docs:` field was introduced. An Enhancement
# (the one type that can change how the game works; a Defect or Exploit fix
# restores documented behaviour) shipped on or after this date without `docs:`
# is warned about on every run; older ones are listed by --docs-backlog instead.
# Most Enhancements are content (areas, items, quests) and just need `docs: none`
# -- see "What counts as a customization" in CLAUDE.md.
# `confirmed` is NOT shipped: it means approved and not yet built.
SHIPPED = {"implemented", "manual", "deployed"}
DOCS_SINCE = "2026-09-23"


def needs_docs(idea: dict) -> bool:
    return (idea.get("type") == "Enhancement" and idea.get("status") in SHIPPED
            and not idea.get("hidden") and not idea.get("dupe_of")
            and not idea.get("docs"))


def main() -> int:
    ap = argparse.ArgumentParser(description=__doc__,
                                 formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("-q", "--quiet", action="store_true",
                    help="print nothing when the file is valid")
    ap.add_argument("--warnings", action="store_true",
                    help="also print advisory warnings (duplicate-idea hints)")
    ap.add_argument("--docs-backlog", action="store_true",
                    help="list every shipped Enhancement with no `docs:` field "
                         "(the player-docs backfill worklist), then exit")
    args = ap.parse_args()

    ED = load_editor()
    data = ED.read_yaml()

    undocumented = [i for i in (data.get("ideas") or []) if needs_docs(i)]
    if args.docs_backlog:
        for i in sorted(undocumented, key=lambda i: str(i.get("date") or "")):
            print(f"{i.get('date') or '----------'}  {i['id']:<44} {i.get('title', '')}")
        print(f"{len(undocumented)} shipped Enhancement(s) with no docs: field",
              file=sys.stderr)
        return 0
    errors, warnings = ED.validate_document(
        data.get("ideas") or [],
        data.get("groups") or [],
        data.get("players") or [],
        data.get("epics") or [],
    )

    # Advisory only, and deliberately not an error: the cap is enforced against
    # a title being WRITTEN (roadmap-editor.validate_title_lengths), because the
    # 41 titles that predate it would otherwise block every save in the GUI.
    # There is no baseline to compare against here, so all this can do is count.
    long_titles = ED.over_long_titles(data.get("ideas") or [])
    if long_titles:
        warnings = list(warnings) + [
            f"{len(long_titles)} title(s) predate the {ED.MAX_TITLE_LEN}-char "
            f"Discord thread-name cap and have to be trimmed the next time they "
            f"are edited (longest: {max(long_titles, key=lambda x: x[1])[0]} at "
            f"{max(n for _, n in long_titles)}). Only the ones still OPEN with "
            f"no thread yet gain anything from being trimmed now — a thread name "
            f"is fixed at creation and nwnbot has no rename action."]

    # Advisory: a player-facing change shipped since the field existed, with nowhere
    # to read about it. Older items are the --docs-backlog worklist, not a warning.
    recent = [i["id"] for i in undocumented if str(i.get("date") or "") >= DOCS_SINCE]
    if recent:
        warnings = list(warnings) + [
            f"{len(recent)} shipped Enhancement(s) have no docs: field. If it changes how "
            f"the game works compared to stock NWN, document it (docs.manual/Customizations/, "
            f"then bin/gen-customizations-hub.py) and set docs: to that page#anchor; if it is "
            f"content (an area, item, quest, boss...), set docs: none: "
            + ", ".join(recent)]

    if args.warnings or recent:
        for w in warnings if args.warnings else warnings[-1:]:
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
