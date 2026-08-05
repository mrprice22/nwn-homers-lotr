#!/usr/bin/env python3
"""Backfill `kind:` on every manual_step in roadmap.yaml.

`kind` is what makes the hand-off backlog reportable: the editor's Toolset Queue
shows the steps you can do in a toolset sitting, the UAT Queue the ones you can
do from the game client, and the in-game Recent Updates board splits "validated"
from "still needs testing" on whether an idea has an open `uat` step left. None
of that works until the ~540 steps written before the field existed are tagged.

This is a one-time pass (it is idempotent, so re-running after new steps land is
fine — it only touches steps that have no `kind` yet, unless --retag).

    python3 bin/roadmap-classify-steps.py            # dry run: show the table
    python3 bin/roadmap-classify-steps.py --diff     # dry run + unified diff
    python3 bin/roadmap-classify-steps.py --apply    # write roadmap.yaml

The heuristic reads the conventional prefixes the steps already use (PLACE:,
UAT, PUBLISH:, ICON UAT/TUNE, ...) and falls back to keywords. It will get some
wrong — that is what the dry run is for, and the editor's per-step dropdown is
the permanent fix. `tester` is deliberately NOT guessed: an untagged UAT step
lands in the queue's "Any / unspecified" bucket, which doubles as the triage
list.
"""
from __future__ import annotations

import argparse
import difflib
import importlib.util
import re
import sys
from pathlib import Path

REPO = Path(__file__).resolve().parent.parent
ED_PATH = REPO / "bin" / "roadmap-editor.py"


def load_editor():
    """Import roadmap-editor.py (hyphenated) for its comment-preserving writer.

    Reusing the editor's serializer rather than round-tripping through PyYAML is
    the whole point: it is the only writer that keeps roadmap.yaml's per-item
    comments and field order intact.
    """
    spec = importlib.util.spec_from_file_location("roadmap_editor", ED_PATH)
    mod = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(mod)
    return mod


ED = load_editor()
GEN = ED.GEN

# Ordered rules: the first hit wins, so the explicit prefixes the steps already
# use beat the loose keyword sweep below them. Anything unmatched -> admin.
RULES: list[tuple[str, str]] = [
    # --- explicit prefixes the existing steps already carry -----------------
    ("uat",     r"^\s*(ICON\s+)?UAT\b"),
    ("uat",     r"^\s*TEST\s+[A-Z0-9]+\s*:"),
    ("toolset", r"^\s*PLACE\b"),
    ("publish", r"^\s*(PUBLISH|REPACK|DEPLOY)\b"),
    # --- keyword sweep ------------------------------------------------------
    # Unambiguous in-game markers first, then the toolset/publish keywords, then
    # the loose "confirm/verify" sweep. Order matters: "verify the placed
    # waypoint's TAG" is toolset work, not UAT, even though it says "verify".
    ("uat",     r"\bUAT\b|\bin[- ]game\b|\blog ?in\b|\bplay ?test"),
    ("publish", r"\brepack\b|\bnwsync\b|\brestart the server\b|\bhak\b"),
    ("publish", r"\brebuild the module\b|\bredeploy\b"),
    ("toolset", r"\bwaypoint\b|\btoolset\b|\bpalette\b|\bblueprint\b"),
    ("toolset", r"\bportrait\b|\bvoiceset\b|\bappearance\b|\bmodelpart\b"),
    ("toolset", r"\binventory icon\b|\bicon\b.{0,40}\b(cycle|tune|read)"),
    ("toolset", r"\bplace\b.{0,60}\b(waypoint|creature|placeable|instance)\b"),
    ("uat",     r"\b(confirm|verify|check) (that|the|it|they|he|she|you)\b"),
    ("uat",     r"\bspawn\b.{0,80}\b(confirm|check|verify|look)"),
]
COMPILED = [(kind, re.compile(pat, re.I)) for kind, pat in RULES]


def classify(text: str) -> str:
    for kind, rx in COMPILED:
        if rx.search(text or ""):
            return kind
    return GEN.DEFAULT_STEP_KIND


def short(text: str, width: int = 96) -> str:
    one = " ".join((text or "").split())
    return one if len(one) <= width else one[: width - 1] + "…"


def main() -> int:
    ap = argparse.ArgumentParser(description=__doc__,
                                 formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--apply", action="store_true",
                    help="write roadmap.yaml (default is a dry run)")
    ap.add_argument("--diff", action="store_true",
                    help="dry run, and print the unified diff that --apply would write")
    ap.add_argument("--retag", action="store_true",
                    help="re-classify steps that already carry a kind (destructive "
                         "to hand-triaged values — normally you do not want this)")
    args = ap.parse_args()

    doc = ED.read_yaml()
    ideas = doc.get("ideas") or []
    # roadmap.yaml already carries some pipeline complaints that predate this
    # pass (shipped items with unfinished blocker steps). Tagging a step must
    # not be the thing that has to fix them, so only *new* errors are fatal.
    before_errs = set(GEN.validate(doc) + ED.validate_internal_fields(ideas))

    buckets: dict[str, list[tuple[str, str]]] = {k: [] for k in GEN.STEP_KINDS}
    kept = 0
    changed = 0
    for idea in ideas:
        steps = idea.get("manual_steps")
        if not isinstance(steps, list):
            continue
        for i, s in enumerate(steps):
            # Legacy bare strings become mappings on write; classify them too.
            if isinstance(s, str):
                s = {"step": s, "status": "open", "blocker": False}
                steps[i] = s
            elif not isinstance(s, dict):
                continue
            if s.get("kind") in GEN.STEP_KINDS and not args.retag:
                kept += 1
                continue
            kind = classify(str(s.get("step", "")))
            s["kind"] = kind
            changed += 1
            buckets[kind].append((idea.get("id", "?"), str(s.get("step", ""))))

    for kind in GEN.STEP_KINDS:
        rows = buckets[kind]
        print(f"\n=== {kind}  ({len(rows)} step(s)) "
              + "=" * max(0, 60 - len(kind)))
        for iid, text in rows:
            print(f"  {iid:<38} {short(text)}")

    print(f"\n{changed} step(s) classified, {kept} left alone "
          f"(already tagged; use --retag to redo them).")

    errs = [e for e in GEN.validate(doc) + ED.validate_internal_fields(ideas)
            if e not in before_errs]
    if errs:
        print("\nREFUSING TO WRITE — validation errors introduced by this pass:",
              file=sys.stderr)
        for e in errs:
            print(f"  {e}", file=sys.stderr)
        return 1

    if args.diff:
        before = ED.YAML_PATH.read_text(encoding="utf-8")
        after = ED.replace_ideas_block(before, ideas)
        sys.stdout.writelines(difflib.unified_diff(
            before.splitlines(keepends=True), after.splitlines(keepends=True),
            fromfile="roadmap.yaml", tofile="roadmap.yaml (after)"))

    if not args.apply:
        print("\nDry run — nothing written. Re-run with --apply to write "
              "roadmap.yaml.")
        return 0

    ED.write_document(ideas)
    print(f"\nWrote {ED.YAML_PATH}.")
    return 0


if __name__ == "__main__":
    sys.exit(main())
