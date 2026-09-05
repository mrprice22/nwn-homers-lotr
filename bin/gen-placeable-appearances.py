#!/usr/bin/env python3
"""Index every placeable *appearance* (placeables.2da row) the module can show.

The Palette Finder (bin/gen-palette-map.py) indexes *blueprints*; this indexes
the visual models behind them. It exists for the "Graffiti the Well of Eru"
merit reward (id 301), whose in-game easel lets a player page through every
placeable look in the game before telling the DM which one they want. See
CLAUDE-graffiti.md.

Source of truth is the module's own hak list (unpacked/module.ifo.json ->
Mod_HakList), read through `nwn_resman_cat` exactly the way gen-palette-map.py
reads the standard palettes. HAK PRIORITY MATTERS: in NWN the *first* hak in the
module list wins, while resman's --erfs takes the *last* one, so the list is
reversed before being handed over. Get this backwards and you index cep2da's
2,307-row table instead of cep2_top_2_71's 10,448-row one, silently.

CEP encodes a category in the Label itself, "Category: Name" ("Crystal:
Floating, Red* (Schazzwozzer)"). Base BioWare rows carry no prefix, so they are
bucketed on the first word of their label ("Crate 01" -> Crate), which merges
them into the CEP categories of the same name. Buckets that would hold a single
row are folded into "Misc" rather than becoming 88 one-entry menus.

Dropped: rows with no Label or no ModelName, the "[Deprecated]*" categories,
VFX-only rows and the invisible placeholder models -- none of them are a thing a
player could point at and say "that one".

Output: module-index/placeable_appearances.json (module-index/ is gitignored).
Publish it to the game with bin/publish-placeable-db.py.
"""
import argparse
import datetime
import json
import re
import shutil
import subprocess
import sys
from pathlib import Path

REPO = Path(__file__).resolve().parents[1]
UNPACKED = REPO / "unpacked"
INDEX_DIR = REPO / "module-index"
OUT = INDEX_DIR / "placeable_appearances.json"

# First existing directory wins; both hold the same CEP haks on this host.
HAK_DIRS = [
    Path.home() / ".local/share/Neverwinter Nights/hak",
    Path.home() / "OneDrive/Documents/Neverwinter Nights/hak",
]

# Categories that are never a graffiti candidate.
DROP_CATEGORY_RE = re.compile(r"^\[deprecated\]|^vfx$", re.IGNORECASE)
DROP_MODEL_RE = re.compile(r"^(plc_invisible|invisible)", re.IGNORECASE)
# A graffiti nobody can see is not a graffiti.
DROP_NAME_RE = re.compile(r"^\(?invisible", re.IGNORECASE)


# ---------------------------------------------------------------- themes
#
# CEP's own categories are far too many to be a menu's first level: 289 of them
# is 33 pages of paging before the player sees a single model. So categories are
# grouped into NINE themes -- nine because that is exactly one page of the
# in-game menu, which makes the first level a single screen.
#
# This is a hand-made map, and deliberately so: the category names are CEP's,
# with a long tail of near-synonyms (Bone/Bones, Flower/Flowers, Ruin/Ruins,
# Obelisk/Obelith/Obeloid) that no rule would group sensibly. Re-shuffle it
# freely -- it is just data, and nothing but the menu's shape depends on it.
#
# A category missing from this map lands in THEME_FALLBACK and the generator
# prints it, so a CEP bump that adds categories is noisy rather than silent.
THEME_FALLBACK = "Machines, Games & Oddities"

CATEGORY_THEME = {
    "Nature & Water": [
        "Tree", "TreeDead", "TreeCanopy", "Plant", "Flower", "Flowers", "Fungus",
        "Mushroom", "Weed", "Bush", "Grass", "Ivy", "Roots", "Rock", "Rocks",
        "Boulder", "Cliff", "Landscape", "Fissure", "Hole", "Ice", "Icicles",
        "Snow", "Winter", "Frost", "Water", "Puddle", "Fluid", "Fountain",
        "Well", "Whirlpool", "Undersea", "OceanObj", "Barnacle", "Fish",
        "Fishing", "Garden", "Log", "Woodpile", "Wood", "Path", "Road", "Track",
        "Egg", "Animal", "Web", "Giant Bee Interior", "Mineral", "Gem", "Fog",
        "Waystone", "Pumpkin", "Apple", "Planter", "Farm", "Fire",
    ],
    "Building & Terrain": [
        "Structure", "Oriental", "Stone", "Wall", "WallSeg", "WallDesign",
        "Floor", "FloorCover", "FloorDesign", "Floor Pad", "Floor Disc",
        "Door", "Doorway / Window", "Window", "Trapdoor", "Pillar", "Balcony",
        "Roof", "Chimney", "Fence", "Bars", "Grate", "Ladder", "Ruin", "Ruins",
        "Rubble", "Debris", "Plaza", "Mill", "Millstone", "Railroad", "Post",
        "Awning", "Tent", "Pyramid", "Tori", "Obelisk", "Obelith", "Obeloid",
        "Pedestal", "Metal City", "Metal Wastes", "Oubliette", "Cage", "Screen",
        "Curtain", "Pipe", "Elemental Pillar", "Metal", "Spike",
    ],
    "Furniture & Home": [
        "Chair", "Chairs", "Bench", "Couch", "Cushion", "Cushions", "Pillow",
        "Seat", "Table", "TableObj", "Desk", "Bed", "Bedroll", "Shelf",
        "Bookshelf", "Cabinet", "Armoire", "Dresser", "Chest of Drawers",
        "Stand", "Rack", "Display", "Display Case", "Furniture", "Workbench",
        "Fireplace", "Privy", "Laundry", "Kitchen", "Dinner", "Bowl", "Plate",
        "Mug", "Tankard", "Bottle", "Jars", "Vase", "Urn", "Pot", "Basin",
        "Bucket", "Basket", "Cheese", "Clothing", "Tavern", "Sleeper",
    ],
    "Containers & Trade": [
        "Chest", "Crate", "Box", "Barrel", "Bag", "Treasure", "Coin", "Coins",
        "Trash", "Pile", "Merchant", "Vendor Cart", "Merchant Sign 1", "Trades",
        "Cart", "Wagon", "Wheelbarrow", "Travel", "Ship", "Boat", "Airship",
        "Rope", "Chain", "Net", "Hide", "Scales",
    ],
    "Light & Fire": [
        "Light", "Source Light", "Candle", "Lantern", "Chandelier", "Gas Jet",
        "Fluid Light", "Torch",
    ],
    "Signs, Art & Writing": [
        "Statue", "Graffiti", "WallArt", "WallObj", "Carpet", "Tapestry",
        "Banner", "BannerPole", "Flag", "Sign", "Signpost", "Placard", "Art",
        "Scrawl", "Alphabet 1", "Paper", "Book", "Library", "Map", "Worldmap",
        "Academic", "Music", "Musical", "Lute", "Theater", "Puppet", "Trophy",
        "Mirror", "Head", "Person", "Sundial", "Weathervane", "List", "The",
        "Mask",
    ],
    "Magic & Religion": [
        "Crystal", "Crystal Ball", "Mythallar", "Rune", "Portal", "Z-portal",
        "Vortex", "Altar", "Shrine", "Temple", "Religious", "Offering", "Relic",
        "Pentagram", "Soul", "Wizard", "Wizard Jar", "Alchemy", "Cauldron",
        "Sphere", "Elven", "Dwarven", "Lizardfolk", "silm", "Golem",
        "Homonculus Bottle", "Canopic", "Rainbow", "Font", "Ambient", "Holidays",
    ],
    "Death & Battle": [
        "Corpse", "Bone", "Bones", "Skeleton", "Remains", "Grave", "Impaled",
        "Impaling", "Torture", "Trap", "Floorblood", "Stain", "Splotch",
        "Dummy", "WarObj", "BFObj", "Armor", "Arrow", "Footprint",
    ],
    "Machines, Games & Oddities": [
        "Mech", "Bio-Mechanoid", "Craft", "Tool", "Lever", "Button", "Pressure",
        "Pump", "Craniometer", "Science Tube", "Ornithopter", "T.A.R.D.I.S.",
        "Gaming", "Chess", "Chessboard", "Die", "Danglies", "Misc",
        "Blackout Box", "Windmill", "Giant",
    ],
}

# Flattened for lookup; built once, and it also catches a name typed into two
# themes (which would otherwise silently pick whichever ran last).
_THEME_OF: dict[str, str] = {}
for _theme, _cats in CATEGORY_THEME.items():
    for _c in _cats:
        if _c in _THEME_OF:
            raise SystemExit(f"category {_c!r} is in two themes: "
                             f"{_THEME_OF[_c]!r} and {_theme!r}")
        _THEME_OF[_c] = _theme

# Menu order of the themes: the dict's own order, fallback last.
THEME_ORDER = list(CATEGORY_THEME)


def theme_of(category: str) -> str:
    return _THEME_OF.get(category, THEME_FALLBACK)


def find_tool(name: str) -> str | None:
    """Locate an niv/neverwinter.nim CLI tool: PATH, else ~/.nimble/bin."""
    found = shutil.which(name)
    if found:
        return found
    candidate = Path.home() / ".nimble" / "bin" / name
    return str(candidate) if candidate.exists() else None


def split_2da(line: str) -> list[str]:
    """Split one 2DA row into cells; "****" becomes an empty string."""
    out, i, n = [], 0, len(line)
    while i < n:
        while i < n and line[i] in (" ", "\t"):
            i += 1
        if i >= n:
            break
        if line[i] == '"':
            j = i + 1
            while j < n and line[j] != '"':
                j += 1
            out.append(line[i + 1:j])
            i = j + 1
        else:
            j = i
            while j < n and line[j] not in (" ", "\t"):
                j += 1
            tok = line[i:j]
            out.append("" if tok == "****" else tok)
            i = j
    return out


def module_haks() -> list[str]:
    ifo = json.loads((UNPACKED / "module.ifo.json").read_text())
    return [h["Mod_Hak"]["value"] for h in ifo["Mod_HakList"]["value"]]


def erf_list() -> list[Path]:
    """Existing hak files for the module, in resman order (lowest priority
    first -- i.e. the module's own list reversed)."""
    hak_dir = next((d for d in HAK_DIRS if d.is_dir()), None)
    if hak_dir is None:
        sys.exit("no NWN hak directory found; looked in "
                 + ", ".join(str(d) for d in HAK_DIRS))
    out = []
    for name in reversed(module_haks()):
        p = hak_dir / f"{name}.hak"
        if p.exists():
            out.append(p)
    if not out:
        sys.exit(f"none of the module's haks are present under {hak_dir}")
    return out


def fetch_2da(name: str, erfs: list[Path]) -> str:
    resman = find_tool("nwn_resman_cat")
    if not resman:
        sys.exit("nwn_resman_cat not found (install niv/neverwinter.nim, or put "
                 "it on PATH / in ~/.nimble/bin)")
    userdir = erfs[0].parent.parent
    cmd = [resman, "--userdirectory", str(userdir),
           "--erfs", ",".join(str(p) for p in erfs), name]
    res = subprocess.run(cmd, capture_output=True)
    if res.returncode != 0 or not res.stdout:
        sys.exit(f"could not read {name} from resman:\n"
                 + res.stderr.decode("utf-8", "replace")[-800:])
    return res.stdout.decode("cp1252", "replace")


def bucket_from_label(label: str) -> tuple[str, str]:
    """(category, name) for one Label cell."""
    if ":" in label:
        cat, _, name = label.partition(":")
        return cat.strip().strip("()"), name.strip()
    # Base BioWare row: bucket on the leading word, minus any trailing index.
    first = re.split(r"[\s,]+", label.strip())[0]
    cat = first.rstrip("0123456789").strip(",()")
    return (cat or label.strip()), label.strip()


def build(entries_only: bool = False) -> dict:
    erfs = erf_list()
    text = fetch_2da("placeables.2da", erfs)
    lines = [l for l in text.splitlines() if l.strip()]
    header = split_2da(lines[1])
    # Cell 0 of a data row is the row index, so header columns are 1-indexed.
    col = {h: i + 1 for i, h in enumerate(header)}
    need = ("Label", "ModelName", "Static")
    missing = [c for c in need if c not in col]
    if missing:
        sys.exit(f"placeables.2da is missing column(s): {', '.join(missing)}")

    entries: list[dict] = []
    for line in lines[2:]:
        cells = split_2da(line)
        if len(cells) <= col["ModelName"] or not cells[0].isdigit():
            continue
        label = cells[col["Label"]].strip()
        model = cells[col["ModelName"]].strip()
        if not label or not model:
            continue
        if DROP_MODEL_RE.match(model):
            continue
        cat, name = bucket_from_label(label)
        if DROP_CATEGORY_RE.match(cat) or DROP_NAME_RE.match(name):
            continue
        entries.append({
            "id": int(cells[0]),
            "name": name,
            "category": cat,
            "model": model,
            "static": cells[col["Static"]] == "1",
        })

    # Fold one-entry buckets into Misc so the in-game menu isn't 88 dead ends.
    counts: dict[str, int] = {}
    for e in entries:
        counts[e["category"].lower()] = counts.get(e["category"].lower(), 0) + 1
    for e in entries:
        if counts[e["category"].lower()] < 2:
            e["category"] = "Misc"

    # Canonical spelling per category: the most common casing wins.
    spelling: dict[str, dict[str, int]] = {}
    for e in entries:
        spelling.setdefault(e["category"].lower(), {})
        spelling[e["category"].lower()][e["category"]] = \
            spelling[e["category"].lower()].get(e["category"], 0) + 1
    for e in entries:
        e["category"] = max(spelling[e["category"].lower()].items(),
                            key=lambda kv: kv[1])[0]

    for e in entries:
        e["theme"] = theme_of(e["category"])

    entries.sort(key=lambda e: (e["category"].lower(), e["name"].lower(), e["id"]))
    cats: dict[str, int] = {}
    cat_theme: dict[str, str] = {}
    for e in entries:
        cats[e["category"]] = cats.get(e["category"], 0) + 1
        cat_theme[e["category"]] = e["theme"]

    order = {t: i for i, t in enumerate(THEME_ORDER)}
    order.setdefault(THEME_FALLBACK, len(order))
    themes: dict[str, list[int]] = {}
    for cat, n in cats.items():
        t = themes.setdefault(cat_theme[cat], [0, 0])
        t[0] += 1                       # categories in the theme
        t[1] += n                       # appearances in the theme

    unmapped = sorted(c for c in cats if c not in _THEME_OF)
    if unmapped:
        print(f"  note: {len(unmapped)} category(ies) not in CATEGORY_THEME, "
              f"filed under {THEME_FALLBACK!r}: " + ", ".join(unmapped))

    return {
        "built": datetime.datetime.now().astimezone().isoformat(timespec="seconds"),
        "source": " + ".join(p.name for p in erfs),
        "themes": [{"name": t, "categories": v[0], "count": v[1]}
                   for t, v in sorted(themes.items(),
                                      key=lambda kv: order.get(kv[0], 99))],
        "categories": [{"name": k, "count": v, "theme": cat_theme[k]}
                       for k, v in sorted(cats.items(),
                                          key=lambda kv: (order.get(cat_theme[kv[0]], 99),
                                                          -kv[1], kv[0].lower()))],
        "entries": entries,
    }


def main() -> int:
    ap = argparse.ArgumentParser(
        description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--dry-run", action="store_true",
                    help="print the summary, write nothing")
    args = ap.parse_args()

    data = build()
    print(f"{len(data['entries'])} appearances in {len(data['categories'])} "
          f"categories / {len(data['themes'])} themes, from {data['source']}")
    for t in data["themes"]:
        print(f"  {t['name']:<28} {t['categories']:3} categories "
              f"{t['count']:5} appearances")
    if args.dry_run:
        return 0
    INDEX_DIR.mkdir(exist_ok=True)
    OUT.write_text(json.dumps(data, indent=1) + "\n", encoding="utf-8")
    print(f"wrote {OUT.relative_to(REPO)}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
