#!/usr/bin/env python3
"""Journal reference check (build-time smoke test).

The wiki's Quests section is built from the categories in module.jrl.json, and
the engine silently drops a journal write whose tag has no category: no error,
no log, and no journal entry for the player. Théoden's Isengard quest shipped
that way for years ("isengard" was never a category), and so did Barliman's
South Greenway rumour. Players reported the quests missing from the wiki, not
the missing journal entry (roadmap item anaralias-what).

The invariant this enforces:

    every journal write in reachable content names a category that exists in
    module.jrl.json and, when the entry number is a literal, an entry that
    exists in that category.

Journal writes come from two places:
  * a conversation node's Quest / QuestEntry fields;
  * AddJournalQuestEntry("tag", N, ...) or AddJournalQuestEntry(CONST, N, ...)
    in a script, with CONST resolved from any `const string` in unpacked/.

A conversation is checked only if something can open it: a Conversation field
on a placed instance, on a blueprint that is placed, in an encounter or named by
a script, or its resref as a string literal in a script. That filters out the
original-campaign dialogs and creatures still in the tree.
Scripts cannot be filtered that way (event hooks and includes), so the dead
ones are listed with a reason in tests/journal_refs_ignore.json.

Exits 0 when every reachable write resolves, 1 otherwise.
"""

import fnmatch
import glob
import json
import os
import re
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
SRC = os.path.join(ROOT, "unpacked")
IGNORE = os.path.join(ROOT, "tests", "journal_refs_ignore.json")

CALL = re.compile(r'AddJournalQuestEntry\s*\(\s*("([^"]*)"|([A-Za-z_]\w*))\s*,\s*(\d+)?')
CONST = re.compile(r'\bconst\s+string\s+([A-Za-z_]\w*)\s*=\s*"([^"]*)"')
COMMENTS = re.compile(r'//[^\n]*|/\*.*?\*/', re.S)
STRLIT = re.compile(r'"([A-Za-z0-9_]{1,16})"')


def load(path):
    with open(path, encoding="utf-8") as f:
        return json.load(f)


def categories():
    """tag.lower() -> (tag, {entry ids}). The engine matches tags case-insensitively."""
    jrl = load(os.path.join(SRC, "module.jrl.json"))
    out = {}
    for cat in jrl["Categories"]["value"]:
        tag = cat["Tag"]["value"]
        ids = {e["ID"]["value"] for e in cat["EntryList"]["value"]}
        out[tag.lower()] = (tag, ids)
    return out


def walk_conversations(obj, found):
    if isinstance(obj, dict):
        conv = obj.get("Conversation")
        if isinstance(conv, dict) and conv.get("value"):
            found.add(conv["value"].lower())
        for v in obj.values():
            walk_conversations(v, found)
    elif isinstance(obj, list):
        for v in obj:
            walk_conversations(v, found)


def main():
    cats = categories()
    patterns = [k.lower() for k in load(IGNORE) if not k.startswith("_")]

    scripts = {}
    for path in glob.glob(os.path.join(SRC, "*.nss")):
        with open(path, encoding="utf-8", errors="replace") as f:
            scripts[os.path.basename(path)[:-4].lower()] = COMMENTS.sub("", f.read())

    ignore = {n for n in scripts if any(fnmatch.fnmatchcase(n, p) for p in patterns)}
    used_patterns = {p for p in patterns if any(fnmatch.fnmatchcase(n, p) for n in scripts)}

    consts = {}
    for text in scripts.values():
        for name, value in CONST.findall(text):
            consts.setdefault(name, set()).add(value)

    # Resrefs a live script names (spawned creatures, started conversations).
    named = set()
    for name, text in scripts.items():
        if name not in ignore:
            named.update(s.lower() for s in STRLIT.findall(text))

    # Blueprints that can end up in the world: placed, in an encounter pool,
    # or named by a script. An unused blueprint's conversation is dead.
    live_bp = set(named)
    for path in glob.glob(os.path.join(SRC, "*.ute.json")):
        for c in load(path).get("CreatureList", {}).get("value", []):
            live_bp.add(c.get("ResRef", {}).get("value", "").lower())

    # Conversations something can open.
    reachable = set(named)
    for path in glob.glob(os.path.join(SRC, "*.git.json")):
        walk_conversations(load(path), reachable)
    for pattern in (".utc.json", ".utp.json"):
        for path in glob.glob(os.path.join(SRC, "*" + pattern)):
            if os.path.basename(path)[:-len(pattern)].lower() in live_bp:
                walk_conversations(load(path), reachable)

    writes = []  # (source, tag, entry or None)
    for path in sorted(glob.glob(os.path.join(SRC, "*.dlg.json"))):
        name = os.path.basename(path)[:-len(".dlg.json")]
        if name.lower() not in reachable:
            continue
        dlg = load(path)
        for key in ("EntryList", "ReplyList"):
            for i, node in enumerate(dlg[key]["value"]):
                tag = node.get("Quest", {}).get("value")
                if tag:
                    entry = node.get("QuestEntry", {}).get("value")
                    writes.append((f"{name}.dlg {key[0]}{i}", tag, entry))

    for name, text in sorted(scripts.items()):
        if name in ignore:
            continue
        for m in CALL.finditer(text):
            literal, ident, entry = m.group(2), m.group(3), m.group(4)
            entry = int(entry) if entry else None
            if literal is not None:
                writes.append((f"{name}.nss", literal, entry))
            elif ident in consts:
                for value in sorted(consts[ident]):
                    writes.append((f"{name}.nss ({ident})", value, entry))
            # Anything else is a runtime variable (a parameter, a table
            # lookup); its values are not knowable here.

    problems = []
    for source, tag, entry in writes:
        hit = cats.get(tag.lower())
        if hit is None:
            problems.append(f"  {source}: journal tag '{tag}' has no category in module.jrl.json")
        elif entry is not None and entry not in hit[1]:
            problems.append(f"  {source}: '{hit[0]}' has no entry {entry} "
                            f"(has {sorted(hit[1])})")

    for pat in sorted(set(patterns) - used_patterns):
        problems.append(f"  tests/journal_refs_ignore.json: '{pat}' matches no script - remove it")

    if problems:
        print(f"FAIL: {len(problems)} journal write(s) go nowhere; the engine drops "
              f"them silently and the quest is missing from the journal and the wiki:\n")
        print("\n".join(problems))
        print("\nAdd the category/entry to unpacked/module.jrl.json, fix the tag, or "
              "(dead code only) list the script in tests/journal_refs_ignore.json.")
        return 1

    print(f"OK: {len(writes)} journal writes all resolve to a category "
          f"({len(ignore)} dead legacy script(s) ignored).")
    return 0


if __name__ == "__main__":
    sys.exit(main())
