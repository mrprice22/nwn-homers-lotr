#!/usr/bin/env python3
"""Apply a JSON patch of per-idea fields to roadmap.yaml.

**This is how an agent writes to roadmap.yaml — never by hand-editing the file.**
The patch is {id: {field: value, ...}}; a null value deletes the field. Writing
goes through the roadmap editor's own serializer, so the output is byte-identical
to what the GUI would produce (comments preserved, canonical field order) and is
validated before anything is written.

Why it matters that agents come through here: the write takes the same file lock
the editor holds, and it rewrites only the ideas named in the patch. The admin
can therefore be editing some *other* item in the GUI at the same time and their
save will merge cleanly instead of hitting a conflict. A hand-edit of the whole
file defeats both of those.

    python3 bin/roadmap-apply-patch.py patch.json [--dry-run]
    python3 bin/roadmap-apply-patch.py patch.json --new    # ids may not exist yet

--new lets a patch CREATE ideas as well as update them, so agents can file a
finding without hand-editing the file and losing the lock/merge behaviour above.
Every created entry is forced to `hidden: true` regardless of what the patch
says: a proposal must cost the admin nothing until they choose to unhide it, and
hidden keeps it off both the public roadmap page and the in-game Recent Updates
sign. Ids that already exist are still updated, not duplicated.
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
    allow_new = "--new" in sys.argv
    if not args:
        print(__doc__)
        return 2

    ed = load_editor()
    import yaml

    path = REPO / "roadmap.yaml"
    # Held across read→validate→write, so a GUI save landing mid-patch can't be
    # lost (and vice versa). Same lock bin/roadmap-editor.py takes on every POST.
    with ed.yaml_lock(timeout=60.0):
        return _apply(ed, yaml, path, args[0], dry, allow_new)


def _apply(ed, yaml, path, patch_file, dry, allow_new=False) -> int:
    text = path.read_text(encoding="utf-8")
    doc = yaml.load(text, Loader=ed._YamlLoader)
    ideas = doc["ideas"]
    by_id = {i["id"]: i for i in ideas}

    patch = json.loads(Path(patch_file).read_text())
    unknown = [k for k in patch if k not in by_id]
    if unknown and not allow_new:
        print(f"error: unknown idea id(s): {unknown}")
        print("       pass --new to create them")
        return 1

    for iid in unknown:
        # Minimal skeleton; the patch supplies the rest and validate_document
        # below refuses anything still missing. hidden is forced, not defaulted.
        idea = {"id": iid, "title": iid, "group": "qol", "status": "new",
                "hidden": True, "type": "Enhancement"}
        ideas.append(idea)
        by_id[iid] = idea
        print(f"created {iid}")

    for iid, fields in patch.items():
        idea = by_id[iid]
        for field, value in fields.items():
            if value is None:
                idea.pop(field, None)
            else:
                idea[field] = value
        if iid in unknown:
            idea["hidden"] = True   # non-negotiable for an agent-created entry
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
    yaml.load(new, Loader=ed._YamlLoader)  # hand-rolled emitter; prove it parses

    if dry:
        print(f"dry run OK — {len(patch)} idea(s) would change")
        return 0
    path.write_text(new, encoding="utf-8")
    print(f"patched {len(patch)} idea(s) in roadmap.yaml")
    return 0


if __name__ == "__main__":
    sys.exit(main())
