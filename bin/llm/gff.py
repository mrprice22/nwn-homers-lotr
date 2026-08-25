"""Safe reads and writes of GFF-as-JSON fields under unpacked/.

Two things here are load-bearing and easy to get wrong:

1. **Serialization must round-trip byte-for-byte.** `nwn_gff` writes
   `json.dumps(..., indent=2, ensure_ascii=False)` plus a trailing newline.
   Verified against a 300-file sample: that exact combination reproduces every
   file unchanged, and `ensure_ascii=True` does not (it would rewrite every
   "Carn Dum" with a circumflex into a \\u escape and blow up the diff).

2. **An empty cexolocstring has two spellings.** Both `{"value": {}}` and
   `{"value": {"0": ""}}` occur in this tree, so "is it blank" and "make it
   blank" both have to handle each. Language id "0" is English.
"""
from __future__ import annotations

import json
import os
import tempfile
from pathlib import Path
from typing import Any

ENGLISH = "0"


# -- file io --------------------------------------------------------------
def load(path: Path | str) -> dict:
    return json.loads(Path(path).read_text(encoding="utf-8"))


def dump(path: Path | str, data: dict) -> None:
    """Atomic write in nwn_gff's exact formatting."""
    path = Path(path)
    text = json.dumps(data, indent=2, ensure_ascii=False) + "\n"
    fd, tmp = tempfile.mkstemp(dir=str(path.parent), prefix=path.name, suffix=".tmp")
    try:
        with os.fdopen(fd, "w", encoding="utf-8") as fh:
            fh.write(text)
        os.replace(tmp, path)
    except BaseException:
        Path(tmp).unlink(missing_ok=True)
        raise


# -- localized strings ----------------------------------------------------
def read_loc(data: dict, field: str, lang: str = ENGLISH) -> str:
    """Text of a cexolocstring field. '' when absent or blank, in either spelling."""
    node = data.get(field) or {}
    value = node.get("value")
    if isinstance(value, dict):
        return str(value.get(lang) or "").strip()
    return str(value or "").strip()


def write_loc(data: dict, field: str, text: str, lang: str = ENGLISH) -> None:
    """Set a cexolocstring field, creating the node if the blueprint lacks it."""
    node = data.get(field)
    if not isinstance(node, dict) or "type" not in node:
        node = {"type": "cexolocstring", "value": {}}
        data[field] = node
    if not isinstance(node.get("value"), dict):
        node["value"] = {}
    node["value"][lang] = text


def read_str(data: dict, field: str) -> str:
    """Text of a plain cexostring field (Comment, Comments, Tag)."""
    node = data.get(field) or {}
    return str(node.get("value") or "").strip()


def write_str(data: dict, field: str, text: str, gff_type: str = "cexostring") -> None:
    node = data.get(field)
    if not isinstance(node, dict) or "type" not in node:
        node = {"type": gff_type, "value": ""}
        data[field] = node
    node["value"] = text


# -- ledger field paths ---------------------------------------------------
# The ledger records a field as a dotted path so a revert needs no task code:
#   "DescIdentified.value.0"   a localized string
#   "Comments.value"           a plain string
def _step(node: Any, part: str) -> Any:
    """One hop along a dotted path. Handles lists as well as dicts.

    Conversation text lives at EntryList.value.<n>.Text.value.0, and EntryList's
    `value` is a JSON array -- so a path walker that only knows dicts cannot
    reach any dialogue at all.
    """
    if isinstance(node, list):
        try:
            index = int(part)
        except ValueError:
            return None
        return node[index] if -len(node) <= index < len(node) else None
    if isinstance(node, dict):
        return node.get(part)
    return None


def read_path(data: dict, path: str) -> Any:
    node: Any = data
    for part in path.split("."):
        node = _step(node, part)
        if node is None:
            return None
    return node


def write_path(data: dict, path: str, value: Any) -> None:
    """Set a dotted path, creating intermediate dicts. `None` deletes the leaf.

    Deleting is how a revert restores a field that did not exist before, which
    matters: leaving `{"0": ""}` behind where the original had `{}` would make
    the revert look clean in the ledger but leave a diff in git.
    """
    parts = path.split(".")
    node: Any = data
    for part in parts[:-1]:
        nxt = _step(node, part)
        if nxt is None:
            if isinstance(node, list):
                raise KeyError(f"cannot create index {part!r} in a list: {path}")
            nxt = {}
            node[part] = nxt
        node = nxt
    leaf = parts[-1]
    if isinstance(node, list):
        # A list slot always exists or it does not; there is nothing to delete.
        node[int(leaf)] = value
    elif value is None:
        node.pop(leaf, None)
    else:
        node[leaf] = value


def resref_of(path: Path | str) -> str:
    """`unpacked/foo.uti.json` -> `foo`. Blueprint filename IS its ResRef."""
    name = Path(path).name
    for suffix in (".uti.json", ".utc.json", ".utp.json", ".utm.json",
                   ".are.json", ".git.json", ".gic.json", ".dlg.json",
                   ".utw.json", ".utt.json", ".ute.json", ".utd.json"):
        if name.endswith(suffix):
            return name[: -len(suffix)]
    return Path(name).stem
