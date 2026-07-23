#!/usr/bin/env python3
"""File orphan blueprints into their PaletteID-correct toolset-palette category.

Blueprints that exist in unpacked/ but were never filed into a custom palette
category (`*palcus.itp.json`) don't appear in the NWN toolset's palette tree at
all -- a DM can't find them to drag into an area (e.g. `slot_token`, the "Rune of
Expansion"). This happens when blueprints are added out-of-band (git / nasher
import) without a toolset "Save Module", which is what normally regenerates the
palette.

CRITICAL: the toolset places every blueprint by its **PaletteID** field -- the
category whose `ID` byte equals the blueprint's `PaletteID` (with a base-item /
appearance fallback when PaletteID is absent). It regenerates the whole custom
palette from PaletteIDs on each save. So an entry hand-placed in a category that
disagrees with the blueprint's PaletteID is transient -- the next toolset save
relocates it (this is what made `slot_token` appear to "move"/"disappear"). This
tool therefore files each orphan at its **PaletteID home**, matching what the
toolset would do, so placements are stable across toolset saves.

Placement per orphan:
  1. PaletteID set AND a category with that ID exists -> that category.
  2. else fallback: learned base-item (items) / appearance (creatures/placeables)
     category, else the "Module Specific*" top-level catch-all.

APPEND-ONLY: existing entries are never moved or removed. This is essential --
the palette also lists ~272 CEP hak blueprints that aren't in unpacked/;
regenerating from scratch would delete them.

The paired `tests/check_palette_coverage.py` smoke gate fails the repack until
every blueprint is filed, so run this (`--apply`) after adding new blueprints.
A toolset "Save Module" achieves the same re-filing.

STANDALONE: never touches git or the wiki. Dry-run by default; pass --apply to
rewrite the `.itp.json` files. Idempotent.
"""
import argparse
import importlib.util
import json
import sys
from collections import Counter
from pathlib import Path

REPO = Path(__file__).resolve().parent.parent
UNPACKED = REPO / "unpacked"


def _load_gen():
    """Import bin/gen-palette-map.py for its shared TLK / name helpers."""
    path = REPO / "bin" / "gen-palette-map.py"
    spec = importlib.util.spec_from_file_location("gen_palette_map", path)
    mod = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(mod)
    return mod


GEN = _load_gen()

# Signal field per palette type used to learn categorization. Types absent here
# (door/encounter/store/trigger/waypoint) have no learnable signal -> fallback.
SIGNAL_FIELD = {
    "item": "BaseItem",
    "creature": "Appearance_Type",
    "placeable": "Appearance",
}

# Top-level categories we never *learn from* (an orphan should not be sent to
# Plot Item / Tutorial / the CEP admin subtrees just because members live there).
EXCLUDE_ROOTS = {
    "Plot Item", "Tutorial", "Module Specific*", "* CEP 2 Custom Palette",
}
# Fallback category (top-level) for orphans with no learnable signal.
FALLBACK_CAT = "Module Specific*"


def gv(node, key):
    """Value of a GFF field on a blueprint dict, or None."""
    f = node.get(key)
    return f.get("value") if isinstance(f, dict) else None


def blueprint_signal(resref: str, ext: str, field: str):
    f = UNPACKED / f"{resref}.{ext}.json"
    if not f.exists():
        return None
    try:
        return gv(json.loads(f.read_text()), field)
    except (OSError, ValueError):
        return None


def index_tree(entries, path, tlk, path_index, id_index, present, root):
    """Walk a palcus MAIN list, recording category indexes and present resrefs.

    `path` is the list of category names from the root to this level.
      * path_index: path-tuple -> category node (for the base-item fallback)
      * id_index:   category ID byte -> (node, path-tuple) (for PaletteID lookup)
      * present:    resref -> (parent-path-tuple, top-level root name)
    """
    for node in entries:
        if "RESREF" in node:
            present[node["RESREF"]["value"]] = (tuple(path), root)
        child = node.get("LIST")
        if child and isinstance(child.get("value"), list):
            cat = GEN.node_category_name(node, tlk)
            croot = root if path else cat
            cid = node.get("ID", {}).get("value")
            path_index[tuple(path + [cat])] = node
            if isinstance(cid, int) and cid not in id_index:
                id_index[cid] = (node, tuple(path + [cat]))
            index_tree(child["value"], path + [cat], tlk,
                       path_index, id_index, present, croot)


def learn_categories(present, resref_ext, ext, field):
    """signal value -> Counter(category-path-tuple) from filed blueprints."""
    learned = {}
    for resref, (path, root) in present.items():
        if resref not in resref_ext:
            continue  # resref belongs to a different type sharing the palette
        if root in EXCLUDE_ROOTS:
            continue
        sig = blueprint_signal(resref, ext, field)
        if sig is None:
            continue
        learned.setdefault(sig, Counter())[path] += 1
    return learned


def free_id_byte(path_index) -> int:
    used = set()
    for node in path_index.values():
        v = node.get("ID", {}).get("value")
        if isinstance(v, int):
            used.add(v)
    for i in range(1, 256):
        if i not in used:
            return i
    raise RuntimeError("no free palette category ID byte")


def ensure_fallback(main_list, path_index, name: str):
    """Return the LIST value of the top-level fallback category, creating it."""
    node = path_index.get((name,))
    if node is None:
        node = {"__struct_id": 0,
                "ID": {"type": "byte", "value": free_id_byte(path_index)},
                "NAME": {"type": "cexostring", "value": name},
                "LIST": {"type": "list", "value": []}}
        main_list.append(node)
        path_index[(name,)] = node
    if "LIST" not in node:  # existing empty category node (e.g. Module Specific*)
        node["LIST"] = {"type": "list", "value": []}
    return node["LIST"]["value"]


def leaf(resref: str, name: str) -> dict:
    return {"__struct_id": 0,
            "NAME": {"type": "cexostring", "value": name},
            "RESREF": {"type": "resref", "value": resref}}


def insert_sorted(lst: list, new_leaf: dict):
    """Insert a leaf name-sorted among a category LIST's existing RESREF leaves.

    Sub-category nodes keep their positions; the leaf lands before the first
    existing leaf with a greater display name, so a later toolset save (which
    name-sorts) produces no reordering churn.
    """
    key = new_leaf["NAME"]["value"].lower()
    for i, n in enumerate(lst):
        if "RESREF" in n and n.get("NAME", {}).get("value", "").lower() > key:
            lst.insert(i, new_leaf)
            return
    lst.append(new_leaf)


def process(stem, typ, ext, tlk, names, apply, log):
    f = UNPACKED / f"{stem}.itp.json"
    if not f.exists():
        return 0, 0
    itp = json.loads(f.read_text())
    main_list = itp.get("MAIN", {}).get("value", [])

    path_index: dict[tuple, dict] = {}
    id_index: dict[int, tuple] = {}
    present: dict[str, tuple] = {}
    index_tree(main_list, [], tlk, path_index, id_index, present, "")

    # All blueprint resrefs of this type on disk.
    disk = {p.name[:-len(f".{ext}.json")] for p in UNPACKED.glob(f"*.{ext}.json")}
    orphans = sorted(disk - set(present))
    if not orphans:
        return 0, 0

    field = SIGNAL_FIELD.get(typ)
    learned = learn_categories(present, disk, ext, field) if field else {}

    filed_pid = filed_fb = 0
    dist: Counter = Counter()
    for resref in orphans:
        name = names.get(resref) or GEN.blueprint_name(resref, ext) or resref
        pid = blueprint_signal(resref, ext, "PaletteID")
        # 1) PaletteID home -- matches the toolset, so it won't be relocated.
        if isinstance(pid, int) and pid in id_index:
            node, tpath = id_index[pid]
            insert_sorted(node["LIST"]["value"], leaf(resref, name))
            dist[" > ".join(tpath)] += 1
            filed_pid += 1
            continue
        # 2) Fallback: learned base-item/appearance category, else Module Specific*.
        target_path = None
        if field:
            cats = learned.get(blueprint_signal(resref, ext, field))
            if cats:
                target_path = cats.most_common(1)[0][0]
        if target_path and target_path in path_index:
            insert_sorted(path_index[target_path]["LIST"]["value"],
                          leaf(resref, name))
            dist[" > ".join(target_path) + " (fallback)"] += 1
        else:
            insert_sorted(ensure_fallback(main_list, path_index, FALLBACK_CAT),
                          leaf(resref, name))
            dist[FALLBACK_CAT + " (fallback)"] += 1
        filed_fb += 1

    log.append(f"  {typ}: filed {len(orphans)} "
               f"({filed_pid} by PaletteID, {filed_fb} fallback)")
    for cat, n in dist.most_common(8):
        log.append(f"      {n:>4}  {cat}")

    if apply:
        f.write_text(json.dumps(itp, indent=2, ensure_ascii=False) + "\n")
    return len(orphans), filed_fb


def main() -> int:
    ap = argparse.ArgumentParser(
        description=__doc__,
        formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--apply", action="store_true",
                    help="write the .itp.json files (default: dry-run report).")
    ap.add_argument("--cep-tlk", type=Path, default=None,
                    help="Fuller CEP tlk for category names (see gen-palette-map.py).")
    args = ap.parse_args()

    dialog = GEN.load_tlk(REPO / "tlk" / "dialog.tlk")
    cep_path = args.cep_tlk or next(
        (p for p in GEN.CEP_TLK_CANDIDATES if p.exists()), None)
    cep = GEN.load_tlk(cep_path) if cep_path and cep_path.exists() else None
    tlk = GEN.TlkResolver(dialog, cep)
    names = GEN.build_resref_names()

    log: list[str] = []
    total = total_fb = 0
    for stem, (typ, ext) in GEN.PALETTES.items():
        n, fb = process(stem, typ, ext, tlk, names, args.apply, log)
        total += n
        total_fb += fb

    print(f"palette orphans: {total} to file "
          f"({total - total_fb} by PaletteID, {total_fb} fallback)")
    for line in log:
        print(line)
    print("APPLIED — wrote .itp.json files" if args.apply
          else "DRY-RUN — re-run with --apply to write")
    return 0


if __name__ == "__main__":
    sys.exit(main())
