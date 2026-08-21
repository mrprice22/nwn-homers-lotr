#!/usr/bin/env python3
"""Restore manual_step `kind` and `tester` values that GUI saves destroyed.

The roadmap editor's hand-off panel used to model only {step, status, blocker,
step_h}. Because that panel rewrites the WHOLE manual_steps list on save, every
idea opened in the list form had each of its steps re-stamped `kind: admin` (the
default normalize_step() supplies) and its `tester` deleted - silently, with no
diff the admin ever saw. Roughly 393 `kind` and 175 `tester` values went that way
across 17 commits before tests/check_roadmap_step_fields.py started gating it.

The values are not gone: every one of them is in git, in an older revision of
roadmap.yaml. This walks that history newest-first and, for each
(idea id, step text), remembers the most recent `kind` that was not `admin` and
the most recent non-empty `tester`. It then fills those back in - but only where
the working tree has lost them. A `kind` the admin has since set deliberately,
or any step that still carries a real kind, is never touched.

Steps whose text was edited after the loss cannot be matched and are reported as
unrecoverable; run bin/roadmap-classify-steps.py afterwards to re-derive `kind`
heuristically for those.

    python3 bin/roadmap-repair-step-kinds.py            # dry run: report only
    python3 bin/roadmap-repair-step-kinds.py --apply    # write roadmap.yaml

The write goes through bin/roadmap-apply-patch.py's path - the editor's own
serializer, under the editor's file lock, one idea at a time - so the admin can
have the GUI open while this runs.
"""
from __future__ import annotations

import argparse
import importlib.util
import json
import re
import subprocess
import sys
import tempfile
from pathlib import Path

REPO = Path(__file__).resolve().parent.parent
YAML_PATH = REPO / "roadmap.yaml"

DEFAULT_KIND = "admin"


def load_editor():
    spec = importlib.util.spec_from_file_location(
        "ed", REPO / "bin" / "roadmap-editor.py")
    mod = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(mod)
    return mod


def key(text: str) -> str:
    """Match steps on their text, whitespace-normalized.

    The text is the only stable identity a step has - there is no id, and the
    index moves whenever a step is added or removed above it.
    """
    return re.sub(r"\s+", " ", str(text or "")).strip().lower()


def revisions(limit: int | None) -> list[str]:
    out = subprocess.run(
        ["git", "-C", str(REPO), "log", "--format=%H", "--", "roadmap.yaml"],
        capture_output=True, text=True, check=True).stdout.split()
    return out[:limit] if limit else out


def blob(rev: str) -> str | None:
    r = subprocess.run(["git", "-C", str(REPO), "show", f"{rev}:roadmap.yaml"],
                       capture_output=True, text=True)
    return r.stdout if r.returncode == 0 else None


def harvest(ed, yaml, revs, wanted: set[tuple[str, str]], verbose: bool):
    """{(idea id, step key): {"kind":…, "tester":…}} from history, newest first.

    Only keys in `wanted` are collected, and a key is dropped from the search as
    soon as both fields are found, so a long history stops being parsed the
    moment it has nothing left to say.
    """
    found: dict[tuple[str, str], dict] = {}
    todo = set(wanted)
    for n, rev in enumerate(revs, 1):
        if not todo:
            break
        text = blob(rev)
        if text is None:
            continue
        try:
            doc = yaml.load(text, Loader=ed._YamlLoader) or {}
        except Exception:
            continue                       # a revision that never parsed cleanly
        for idea in (doc.get("ideas") or []):
            iid = idea.get("id")
            for s in (idea.get("manual_steps") or []):
                if not isinstance(s, dict):
                    continue
                k = (iid, key(s.get("step")))
                if k not in todo:
                    continue
                slot = found.setdefault(k, {})
                kind = s.get("kind")
                if "kind" not in slot and kind and kind != DEFAULT_KIND:
                    slot["kind"] = kind
                tester = str(s.get("tester") or "").strip()
                if "tester" not in slot and tester:
                    slot["tester"] = tester
                if "kind" in slot and "tester" in slot:
                    todo.discard(k)
        if verbose:
            print(f"  …{n}/{len(revs)} revisions, {len(todo)} steps still "
                  f"unresolved", file=sys.stderr)
    return found


def main() -> int:
    ap = argparse.ArgumentParser(description=__doc__,
                                 formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--apply", action="store_true",
                    help="write roadmap.yaml (default is a dry-run report)")
    ap.add_argument("--max-revs", type=int, default=None,
                    help="only search this many revisions back")
    ap.add_argument("-v", "--verbose", action="store_true",
                    help="progress while walking history")
    args = ap.parse_args()

    ed = load_editor()
    import yaml

    doc = yaml.load(YAML_PATH.read_text(encoding="utf-8"),
                    Loader=ed._YamlLoader) or {}
    ideas = doc.get("ideas") or []

    # Every step that has lost something. A step keeps whatever it still has:
    # we only ask history about a missing/defaulted field.
    wanted: set[tuple[str, str]] = set()
    for idea in ideas:
        for s in (idea.get("manual_steps") or []):
            if not isinstance(s, dict):
                continue
            needs_kind = (s.get("kind") or DEFAULT_KIND) == DEFAULT_KIND
            needs_tester = not str(s.get("tester") or "").strip()
            if needs_kind or needs_tester:
                wanted.add((idea.get("id"), key(s.get("step"))))

    revs = revisions(args.max_revs)
    print(f"{len(wanted)} step(s) missing a kind and/or tester; searching "
          f"{len(revs)} revision(s) of roadmap.yaml…")
    found = harvest(ed, yaml, revs, wanted, args.verbose)

    patch: dict[str, dict] = {}
    report: list[str] = []
    fixed_kind = fixed_tester = 0
    for idea in ideas:
        iid = idea.get("id")
        steps = idea.get("manual_steps") or []
        touched = False
        for s in steps:
            if not isinstance(s, dict):
                continue
            hit = found.get((iid, key(s.get("step"))))
            if not hit:
                continue
            if (s.get("kind") or DEFAULT_KIND) == DEFAULT_KIND and "kind" in hit:
                s["kind"] = hit["kind"]
                fixed_kind += 1
                touched = True
                report.append(f"  {iid}: kind admin -> {hit['kind']}  "
                              f"| {str(s.get('step'))[:60]}")
            if (not str(s.get("tester") or "").strip()) and "tester" in hit:
                s["tester"] = hit["tester"]
                fixed_tester += 1
                touched = True
                report.append(f"  {iid}: tester -> {hit['tester']!r}  "
                              f"| {str(s.get('step'))[:60]}")
        if touched:
            patch[iid] = {"manual_steps": ed.normalize_steps(steps)}

    for line in report:
        print(line)
    # `found` gets an entry for every step history has ever seen; only the ones
    # that actually yielded a value count as recovered.
    unrecoverable = len(wanted) - len([k for k, v in found.items() if v])
    print(f"\n{fixed_kind} kind + {fixed_tester} tester value(s) recoverable "
          f"across {len(patch)} idea(s); {unrecoverable} step(s) have no "
          f"history to restore from (run bin/roadmap-classify-steps.py for "
          f"those).")

    if not patch:
        return 0
    if not args.apply:
        print("\nDry run — nothing written. Re-run with --apply.")
        return 0

    with tempfile.NamedTemporaryFile("w", suffix=".json", delete=False) as fh:
        json.dump(patch, fh)
        patch_file = fh.name
    try:
        r = subprocess.run([sys.executable,
                            str(REPO / "bin" / "roadmap-apply-patch.py"),
                            patch_file], cwd=str(REPO))
        return r.returncode
    finally:
        Path(patch_file).unlink(missing_ok=True)


if __name__ == "__main__":
    sys.exit(main())
