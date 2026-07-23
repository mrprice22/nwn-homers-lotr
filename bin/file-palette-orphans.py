#!/usr/bin/env python3
"""File orphan blueprints into their matching toolset-palette category.

Blueprints that exist in unpacked/ but were never filed into a custom palette
category (`*palcus.itp.json`) don't appear in the NWN toolset's palette tree at
all -- a DM can't find them to drag into an area (e.g. `slot_token`, the "Rune of
Expansion"). This tool files every such orphan into the *correct existing*
category, learned empirically from the blueprints already in the palette:

  * items      -> by BaseItem
  * creatures  -> by Appearance_Type
  * placeables -> by Appearance

For each signal value we take the majority category among blueprints already
filed under it, ignoring non-gameplay buckets (Plot Item / Tutorial / the CEP
admin subtrees) so orphans land in real gameplay folders. Anything with no
learnable signal falls back to the "Module Specific*" top-level category.

The paired `tests/check_palette_coverage.py` smoke gate fails the repack until
every blueprint is filed, so run this (`--apply`) after adding new blueprints.

STANDALONE: never touches git or the wiki. Dry-run by default; pass --apply to
rewrite the `.itp.json` files. Idempotent -- a blueprint already anywhere in a
real category is left alone, and one filed properly later drops out of the
fallback on the next run.
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


def index_tree(entries, path, tlk, path_index, present, root):
    """Walk a palcus MAIN list, recording path->node and present resrefs.

    `path` is the list of category names from the root to this level. Leaf
    (RESREF) nodes record their resref and the path of their *parent* category
    plus the top-level root name that path descends from.
    """
    for node in entries:
        if "RESREF" in node:
            present[node["RESREF"]["value"]] = (tuple(path), root)
        child = node.get("LIST")
        if child and isinstance(child.get("value"), list):
            cat = GEN.node_category_name(node, tlk)
            croot = root if path else cat
            path_index[tuple(path + [cat])] = node
            index_tree(child["value"], path + [cat], tlk, path_index, present, croot)


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


def process(stem, typ, ext, tlk, names, apply, log):
    f = UNPACKED / f"{stem}.itp.json"
    if not f.exists():
        return 0, 0
    itp = json.loads(f.read_text())
    main_list = itp.get("MAIN", {}).get("value", [])

    path_index: dict[tuple, dict] = {}
    present: dict[str, tuple] = {}
    index_tree(main_list, [], tlk, path_index, present, "")

    # All blueprint resrefs of this type on disk.
    disk = {p.name[:-len(f".{ext}.json")] for p in UNPACKED.glob(f"*.{ext}.json")}
    orphans = sorted(disk - set(present))
    if not orphans:
        return 0, 0

    field = SIGNAL_FIELD.get(typ)
    learned = learn_categories(present, disk, ext, field) if field else {}

    filed_sig = filed_fb = 0
    dist: Counter = Counter()
    # `orphans` is sorted, so appends are deterministic across runs. We append
    # (never reorder existing entries) to keep the diff minimal; the toolset
    # displays each category name-sorted regardless of on-disk order.
    for resref in orphans:
        name = names.get(resref) or GEN.blueprint_name(resref, ext) or resref
        target_path = None
        if field:
            sig = blueprint_signal(resref, ext, field)
            cats = learned.get(sig)
            if cats:
                target_path = cats.most_common(1)[0][0]
        if target_path and target_path in path_index:
            path_index[target_path]["LIST"]["value"].append(leaf(resref, name))
            dist[" > ".join(target_path)] += 1
            filed_sig += 1
        else:
            ensure_fallback(main_list, path_index, FALLBACK_CAT).append(
                leaf(resref, name))
            dist[FALLBACK_CAT + " (fallback)"] += 1
            filed_fb += 1

    log.append(f"  {typ}: filed {len(orphans)} "
               f"({filed_sig} by {field or 'n/a'}, {filed_fb} fallback)")
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
          f"({total - total_fb} categorized, {total_fb} fallback)")
    for line in log:
        print(line)
    print("APPLIED — wrote .itp.json files" if args.apply
          else "DRY-RUN — re-run with --apply to write")
    return 0


if __name__ == "__main__":
    sys.exit(main())
