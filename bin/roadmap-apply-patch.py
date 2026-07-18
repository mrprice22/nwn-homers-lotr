#!/usr/bin/env python3
"""Apply a JSON patch of per-idea fields to roadmap.yaml.

One-off helper for the notes/impl_notes/manual_steps split. The patch is
{id: {field: value, ...}}; a null value deletes the field. Writing goes through
the roadmap editor's own serializer, so the output is byte-identical to what the
GUI would produce (comments preserved, canonical field order) and is validated
before anything is written.

    python3 bin/roadmap-apply-patch.py patch.json [--dry-run]
"""
from __future__ import annotations

import importlib.util
import json
import sys
from pathlib import Path

REPO = Path(__file__).resolve().parent.parent


def load_editor():
    spec = importlib.util.spec_from_file_location("ed", REPO / "bin" / "roadmap-editor.py")
    mod = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(mod)
    return mod


def main() -> int:
    args = [a for a in sys.argv[1:] if not a.startswith("-")]
    dry = "--dry-run" in sys.argv
    if not args:
        print(__doc__)
        return 2

    ed = load_editor()
    import yaml

    path = REPO / "roadmap.yaml"
    text = path.read_text()
    doc = yaml.safe_load(text)
    ideas = doc["ideas"]
    by_id = {i["id"]: i for i in ideas}

    patch = json.loads(Path(args[0]).read_text())
    unknown = [k for k in patch if k not in by_id]
    if unknown:
        print(f"error: unknown idea id(s): {unknown}")
        return 1

    for iid, fields in patch.items():
        idea = by_id[iid]
        for field, value in fields.items():
            if value is None:
                idea.pop(field, None)
            else:
                idea[field] = value
        # Same normalization the editor's POST path applies.
        if idea.get("manual_steps"):
            idea["manual_steps"] = ed.normalize_steps(idea["manual_steps"])
        for field in ("notes", "impl_notes"):
            if idea.get(field):
                idea[field] = ed.sanitize_notes(idea[field])

    errors, warnings = ed.validate_document(ideas, doc.get("groups"), doc.get("players"))
    for w in warnings:
        print(f"warning: {w}")
    if errors:
        for e in errors:
            print(f"error: {e}")
        return 1

    head, prefixes, trailing = ed.split_head_and_prefixes(text)
    body = ed.serialize_ideas(ideas, prefixes, trailing)
    new = ed.replace_block(text, "ideas", body)
    yaml.safe_load(new)  # the emitter is hand-rolled; prove it still parses

    if dry:
        print(f"dry run OK — {len(patch)} idea(s) would change")
        return 0
    path.write_text(new)
    print(f"patched {len(patch)} idea(s) in roadmap.yaml")
    return 0


if __name__ == "__main__":
    sys.exit(main())
