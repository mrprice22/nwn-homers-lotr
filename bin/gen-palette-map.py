#!/usr/bin/env python3
"""Map every blueprint to its location in the in-game toolset palette.

A DM/admin who knows a creature/item/placeable by name often can't find it among
the hundreds of categories and submenus in the toolset's custom palette. This
tool walks every `unpacked/*palcus.itp.json` (the custom palette trees) and emits
a flat, searchable index:

    resref  ->  { name, type, palette:"Top > Sub > ... > Leaf category" }

The output feeds the "Palette Finder" search panel in bin/roadmap-editor.py.

Blueprints that exist in unpacked/ but were never filed into a custom palette
category (script-created / "orphaned" ones — e.g. slot_token) don't appear in the
palette tree at all. They're still indexed here with `in_palette: false` and a
"(not in toolset palette …)" marker, so a search finds them instead of returning
nothing.

STANDALONE / ONE-OFF: this is NOT part of the wiki build or the Publish flow.
Run it (or click "Refresh palette map" in the roadmap editor) after adding or
renaming blueprints you place into a palette category. It never touches git or
docs/.

--- Palette (.itp.json) shape ---
Each file is a GFF "ITP " tree. MAIN is a recursive list of struct nodes:
  * Category node : ID (byte) + a name (STRREF dword TLK ref, or inline NAME
                    cexostring) + a child LIST.
  * Blueprint leaf: RESREF (= the blueprint's filename stem), optionally an
                    override NAME/STRREF.

--- TLK resolution ---
Category STRREF values encode which TLK: ref < 0x01000000 -> base dialog.tlk;
ref >= 0x01000000 -> custom CEP tlk at index (ref - 0x01000000). The repo's
tlk/cep.tlk is an older/smaller CEP2 tlk that can't resolve the high custom
category refs the palette uses, so for those we point at a fuller CEP 2.6 tlk
(cep260.tlk) from the local NWN install (configurable via --cep-tlk). Resolution
falls back gracefully: base categories still resolve from the repo tlk even if
the fuller tlk is absent.

Output: module-index/palette_map.json (module-index/ is gitignored).
"""
import argparse
import datetime
import json
import struct
import sys
from pathlib import Path

REPO = Path(__file__).resolve().parents[1]
UNPACKED = REPO / "unpacked"
INDEX_DIR = REPO / "module-index"
OUT = INDEX_DIR / "palette_map.json"

CUSTOM_TLK_BASE = 0x01000000

# palette file stem -> (blueprint type label, blueprint extension)
PALETTES = {
    "itempalcus": ("item", "uti"),
    "creaturepalcus": ("creature", "utc"),
    "placeablepalcus": ("placeable", "utp"),
    "doorpalcus": ("door", "utd"),
    "encounterpalcus": ("encounter", "ute"),
    "soundpalcus": ("sound", "uts"),
    "storepalcus": ("store", "utm"),
    "triggerpalcus": ("trigger", "utt"),
    "waypointpalcus": ("waypoint", "utw"),
}

# First existing path wins for the fuller CEP tlk (custom category names).
CEP_TLK_CANDIDATES = [
    Path.home() / "OneDrive/Documents/Neverwinter Nights/tlk/cep260.tlk",
    Path.home() / ".local/share/Neverwinter Nights/tlk/cep260.tlk",
    Path.home() / "Downloads/CEP_2.71_full_with_hotfix1/tlk/cep260.tlk",
]


def load_tlk(path: Path) -> list[str]:
    """Parse a TLK V3.0 file into a list of strings indexed by StrRef."""
    data = path.read_bytes()
    if data[:8] != b"TLK V3.0":
        raise ValueError(f"{path}: not a TLK V3.0 file")
    _lang, n, str_off = struct.unpack("<III", data[8:20])
    out: list[str] = []
    table = 20
    for i in range(n):
        e = table + i * 40
        (flags,) = struct.unpack("<I", data[e:e + 4])
        soff, slen = struct.unpack("<II", data[e + 28:e + 36])
        if flags & 1:  # TEXT_PRESENT
            out.append(data[str_off + soff:str_off + soff + slen].decode("latin1"))
        else:
            out.append("")
    return out


class TlkResolver:
    def __init__(self, dialog: list[str], cep: list[str] | None):
        self.dialog = dialog
        self.cep = cep or []
        self.unresolved = 0

    def resolve(self, ref: int) -> str:
        if ref >= CUSTOM_TLK_BASE:
            i = ref - CUSTOM_TLK_BASE
            if i < len(self.cep) and self.cep[i]:
                return self.cep[i]
            self.unresolved += 1
            return f"cep {i}"
        if 0 <= ref < len(self.dialog) and self.dialog[ref]:
            return self.dialog[ref]
        self.unresolved += 1
        return f"dlg {ref}"


def node_category_name(node: dict, tlk: TlkResolver) -> str:
    """Display name for a *category* node: STRREF (TLK) wins, else inline NAME."""
    if "STRREF" in node:
        return tlk.resolve(node["STRREF"]["value"])
    if "NAME" in node:
        return node["NAME"]["value"]
    return ""


def node_inline_name(node: dict, tlk: TlkResolver) -> str:
    """Best inline name for a *leaf* node (override name shown in the palette)."""
    if "NAME" in node:
        return node["NAME"]["value"]
    if "STRREF" in node:
        return tlk.resolve(node["STRREF"]["value"])
    return ""


def build_resref_names() -> dict[str, str]:
    """resref -> authoritative display name, from the wiki's precomputed indexes.

    Optional: module-index/ is gitignored and may be absent on a fresh clone; we
    just skip enrichment (falling back to inline palette names) if so.
    """
    names: dict[str, str] = {}
    idx = INDEX_DIR / "item_index.json"
    if idx.exists():
        for it in json.loads(idx.read_text()).get("items", []):
            rr = it.get("resref")
            if rr and rr not in names:
                names[rr] = (it.get("name") or "").strip()
    cidx = INDEX_DIR / "creature_index.json"
    if cidx.exists():
        for c in json.loads(cidx.read_text()).get("creatures", []):
            rr = c.get("blueprint_resref") or c.get("canonical_resref")
            if rr and rr not in names:
                names[rr] = (c.get("name") or "").strip()
    return names


def blueprint_name(resref: str, ext: str) -> str:
    """Last-resort name: read the blueprint's own LocalizedName/FirstName."""
    f = UNPACKED / f"{resref}.{ext}.json"
    if not f.exists():
        return ""
    try:
        obj = json.loads(f.read_text())
    except (OSError, ValueError):
        return ""
    for key in ("LocalizedName", "FirstName"):
        field = obj.get(key)
        if isinstance(field, dict):
            val = field.get("value")
            if isinstance(val, dict):  # cexolocstring: {"0": "text"}
                for v in val.values():
                    if v:
                        return str(v).strip()
            elif val:
                return str(val).strip()
    return ""


# Top-level palette categories that are module/custom buckets (as opposed to the
# standard Bioware/CEP category tree). Used to flag whether a blueprint sits in
# the "custom palette" section. `Special` holds the Custom 1-5 slots.
CUSTOM_ROOTS = {"Module Specific*", "CEP Specific*", "Special"}


def is_custom_root(root: str) -> bool:
    return root in CUSTOM_ROOTS or root.startswith("* CEP")


def walk(entries: list, path: list[str], typ: str, ext: str,
         tlk: TlkResolver, names: dict[str, str], out: list[dict]):
    for node in entries:
        if "RESREF" in node:
            resref = node["RESREF"]["value"]
            name = (names.get(resref)
                    or node_inline_name(node, tlk)
                    or blueprint_name(resref, ext)
                    or resref)
            root = next((p for p in path if p), "")
            out.append({
                "resref": resref,
                "name": name,
                "type": typ,
                "palette": " > ".join(p for p in path if p),
                "in_palette": True,
                "custom_palette": is_custom_root(root),
            })
        child = node.get("LIST")
        if child and isinstance(child.get("value"), list):
            cat = node_category_name(node, tlk)
            walk(child["value"], path + [cat], typ, ext, tlk, names, out)


# Marker for blueprints that exist in unpacked/ but were never filed into a
# custom toolset-palette category (script-created or "orphaned" blueprints).
# They don't show up in the toolset's palette tree at all — surface them so a
# search still finds them instead of silently returning nothing.
NOT_IN_PALETTE = "(not in toolset palette — blueprint/script only)"


def scan_orphans(seen: set[str], names: dict[str, str], out: list[dict]):
    """Append every blueprint not already listed in a custom palette."""
    for stem, (typ, ext) in PALETTES.items():
        for f in sorted(UNPACKED.glob(f"*.{ext}.json")):
            resref = f.name[:-len(f".{ext}.json")]
            if resref in seen:
                continue
            seen.add(resref)
            name = names.get(resref) or blueprint_name(resref, ext) or resref
            out.append({
                "resref": resref,
                "name": name,
                "type": typ,
                "palette": NOT_IN_PALETTE,
                "in_palette": False,
                "custom_palette": False,
            })


def main() -> int:
    ap = argparse.ArgumentParser(description=__doc__,
                                 formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--cep-tlk", type=Path, default=None,
                    help="Fuller CEP tlk for custom category names "
                         "(default: first of the known cep260.tlk locations).")
    ap.add_argument("-o", "--out", type=Path, default=OUT,
                    help=f"Output path (default: {OUT}).")
    args = ap.parse_args()

    dialog_path = REPO / "tlk" / "dialog.tlk"
    if not dialog_path.exists():
        print(f"error: missing {dialog_path}", file=sys.stderr)
        return 1
    dialog = load_tlk(dialog_path)

    cep_path = args.cep_tlk
    if cep_path is None:
        cep_path = next((p for p in CEP_TLK_CANDIDATES if p.exists()), None)
    cep = None
    if cep_path and cep_path.exists():
        try:
            cep = load_tlk(cep_path)
        except ValueError as e:
            print(f"warning: {e}; custom category names may be unresolved",
                  file=sys.stderr)
            cep_path = None
    else:
        if cep_path:
            print(f"warning: {cep_path} not found; custom category names may be "
                  "unresolved", file=sys.stderr)
        cep_path = None

    tlk = TlkResolver(dialog, cep)
    names = build_resref_names()

    out: list[dict] = []
    for stem, (typ, ext) in PALETTES.items():
        f = UNPACKED / f"{stem}.itp.json"
        if not f.exists():
            continue
        itp = json.loads(f.read_text())
        main_list = itp.get("MAIN", {}).get("value", [])
        walk(main_list, [], typ, ext, tlk, names, out)

    # Blueprints that exist but were never filed into a custom palette category
    # (e.g. script-created items like slot_token) don't appear in the palette
    # tree at all. Add them so a search still surfaces them, flagged in_palette.
    seen = {e["resref"] for e in out}
    scan_orphans(seen, names, out)

    out.sort(key=lambda e: (e["type"], e["name"].lower(), e["resref"]))

    doc = {
        "generated": datetime.datetime.now().isoformat(timespec="seconds"),
        "cep_tlk": str(cep_path) if cep_path else None,
        "count": len(out),
        "entries": out,
    }
    args.out.parent.mkdir(parents=True, exist_ok=True)
    args.out.write_text(json.dumps(doc, indent=1))

    per_type: dict[str, int] = {}
    for e in out:
        per_type[e["type"]] = per_type.get(e["type"], 0) + 1
    orphans = sum(1 for e in out if not e["in_palette"])
    summary = ", ".join(f"{k}={v}" for k, v in sorted(per_type.items()))
    print(f"palette_map: {len(out)} entries ({summary})")
    print(f"  {orphans} not in any custom palette (blueprint/script only)")
    print(f"  unresolved category refs: {tlk.unresolved}"
          f"  cep tlk: {cep_path or '(none)'}")
    print(f"  wrote {args.out}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
