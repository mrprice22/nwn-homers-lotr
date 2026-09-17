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

An `"epics"` key in the patch writes the `epics:` block by the same route:

    {"epics": {"my-epic": {"title": "My Epic", "group": "wiki-tools"}},
     "child-idea": {"epic": "my-epic", "status": "planned"}}

Epics are created when unknown (no --new needed — an epic carries no merit and
no player, so there is nothing to protect) and updated in place otherwise.
`null` deletes a field there too; an epic itself is never deleted from here,
because removing one would orphan every idea pointing at it. Only the two
blocks the patch actually names are rewritten, so the lock/merge story above
holds for epics as well.
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
    # A copy of every title as the file has it, taken before the patch is
    # applied: the title cap is enforced against a title being WRITTEN, never
    # against one already there. See roadmap-editor.validate_title_lengths.
    before = [{"id": i.get("id"), "title": i.get("title")} for i in ideas]
    by_id = {i["id"]: i for i in ideas}

    patch = json.loads(Path(patch_file).read_text())
    # `epics` is a block, not an idea id -- lift it out before anything below
    # treats it as one.
    epic_patch = patch.pop("epics", None) or {}
    epics = doc.get("epics") or []

    unknown = [k for k in patch if k not in by_id]
    if unknown and not allow_new:
        print(f"error: unknown idea id(s): {unknown}")
        print("       pass --new to create them")
        return 1

    for iid in unknown:
        # Minimal skeleton; the patch supplies the rest and validate_document
        # below refuses anything still missing. `planned` because "new" is not a
        # key of gen-roadmap's STATUS, so it fails validation every time and the
        # patch would have had to supply a status to undo it. hidden is forced,
        # not defaulted.
        idea = {"id": iid, "title": iid, "group": "qol", "status": "planned",
                "hidden": True, "type": "Enhancement"}
        ideas.append(idea)
        by_id[iid] = idea
        print(f"created {iid}")

    by_epic = {e["id"]: e for e in epics if isinstance(e, dict) and e.get("id")}
    for eid, fields in epic_patch.items():
        epic = by_epic.get(eid)
        if epic is None:
            epic = {"id": eid, "title": eid, "group": "qol"}
            epics.append(epic)
            by_epic[eid] = epic
            print(f"created epic {eid}")
        for field, value in (fields or {}).items():
            if value is None:
                epic.pop(field, None)
            else:
                epic[field] = value
        if epic.get("notes"):
            epic["notes"] = ed.sanitize_notes(epic["notes"])

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

    # All four blocks, so the epic checks in extra_validate() actually run --
    # bin/roadmap-lint.py passes epics for the same reason.
    errors, warnings = ed.validate_document(ideas, doc.get("groups"),
                                            doc.get("players"), epics)
    errors = list(errors) + ed.validate_title_lengths(ideas, before)
    for w in warnings:
        print(f"warning: {w}")
    if errors:
        for e in errors:
            print(f"error: {e}")
        return 1

    head, prefixes, trailing = ed.split_head_and_prefixes(text)
    new = text
    if patch:
        body = ed.serialize_ideas(ideas, prefixes, trailing)
        new = ed.replace_block(new, "ideas", body)
    if epic_patch:
        # A roadmap.yaml predating the epics feature has no such line at all.
        new = ed.ensure_block(new, "epics", "ideas")
        new = ed.replace_block(new, "epics", ed.serialize_epics(epics))
    yaml.load(new, Loader=ed._YamlLoader)  # hand-rolled emitter; prove it parses

    changed = (f"{len(patch)} idea(s)"
               + (f" + {len(epic_patch)} epic(s)" if epic_patch else ""))
    if dry:
        print(f"dry run OK — {changed} would change")
        return 0
    path.write_text(new, encoding="utf-8")
    print(f"patched {changed} in roadmap.yaml")
    return 0


if __name__ == "__main__":
    sys.exit(main())
