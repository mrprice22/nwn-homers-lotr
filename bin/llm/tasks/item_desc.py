"""item_desc -- the UNIDENTIFIED description: what a player sees before identifying.

Roughly 1,000 items a player can actually obtain carry no description at all:
examining them shows the mechanical property list and nothing else. This writes
`DescIdentified` (the identified text, which is what players read) and leaves
`Description` (the unidentified text) alone.

Risk tier `auto`: the field is empty by definition of the selector, so nothing
human-authored can be overwritten.

Context comes from three places, all already resolved by other tooling:
  * the blueprint's own LocalizedName
  * the wiki's Properties table (see llm/wiki.py -- raw GFF is numeric)
  * item_index.json's `sources`, which say where the item is found in-world

That third one matters more than it looks. "Carried by: Orc Sorcerer (Morannon -
The Black Gate)" grounds the description in this module's world; without it the
model invents a provenance, which is exactly what the invented_names validator
then has to reject.
"""
from __future__ import annotations

import json
from pathlib import Path

if __package__ in (None, ""):
    import pathlib as _pathlib
    import sys as _sys
    _sys.path.insert(0, str(_pathlib.Path(__file__).resolve().parents[2]))

from llm import config, gff, wiki
from llm.tasks.base import CONFIDENCE_NOTE, Item, Task

# The unidentified description -- what a player sees BEFORE identifying an item.
# Round one wrote this text into DescIdentified before the two-field split
# existed, and bin/llm/migrate_descriptions.py relocated all 915 of them here.
# The prompt was always right for this slot (physical only, no mechanics); only
# the target field was wrong.
FIELD = "Description.value.0"

# Base items the player never examines: creature-slot weapons and hides, and the
# CEP dye kits, which are pure UI tools with nothing to say for themselves.
SKIP_BASE = {
    "creaturebludgeonweapon", "creatureslashweapon", "creaturepierceweapon",
    "creatureslashpierceweapon", "creatureitem", "creaturehide",
    "dyekit", "dye", "blank",
}
SKIP_PREFIX = ("dyec", "dyel", "dyem", "sha_pcl_", "npcbuffgear",
               "it_cre", "forge_blank_", "nw_it_creitem")

SYSTEM = f"""You write item descriptions for a Lord of the Rings themed Neverwinter Nights persistent world.

Rules, in order of importance:
1. One or two sentences. Under 300 characters. Never longer.
2. Describe what the item looks like and what it feels like to carry or wield.
3. NEVER restate the mechanical bonuses. The player already sees those on the
   item. No numbers of any kind.
4. Do not invent named people or places. You may use Tolkien's own names and the
   names given to you in the prompt, and nothing else. If you know nothing about
   the item's origin, describe the object itself.
5. Plain ASCII punctuation. Use -- for a dash. No curly quotes, no ellipsis
   character. Do not wrap the description in quotation marks.
6. Tolkien's register: concrete, weathered, unshowy. Not video-game epic.
7. VARY YOUR LANGUAGE. Left alone you reach for the same words every time --
   measured over a real batch, "heavy" appeared in fifteen descriptions out of
   sixteen and six of them opened with "A heavy". Avoid: heavy, weighty, feels,
   unnaturally, seems to, sits upon, to the touch. Do not open every description
   with "A" or "These" plus an adjective; start from the detail, the material,
   the maker or the wear where it reads better. Do not open with "Forged from" --
   that became a quarter of the batch the moment "heavy" was taken away.
10. DO NOT CLAIM A CAPABILITY THE ITEM DOES NOT HAVE. Describe how it looks,
   feels, was made and was used as freely as you like. But do not say it makes
   the bearer quiet, quick, hidden, healed or sharp-eyed unless a property in
   the list above grants that. The NAME IS NOT EVIDENCE -- boots called "of the
   Mirkwood Elf" are not stealthy unless the properties say they are, and
   writing that they are tells the player something false about their own gear.

{CONFIDENCE_NOTE}"""

# Five different things to notice about an object. Rotated deterministically per
# resref so two rings do not both come back as "a heavy band of tarnished silver
# ... sits upon the finger with a weight that", which is what happened without it.
ANGLES = (
    "Focus on how it was made and what it is made of.",
    "Focus on how it feels to hold, wear or wield -- weight, balance, temperature.",
    "Focus on its wear and history: the marks of use, age and repair upon it.",
    "Focus on a small sensory detail -- a sound, a smell, the way light falls on it.",
    "Focus on the impression it gives the person carrying it.",
)

TEMPLATE = """{context}

{angle}

Write the description for this item."""


def _index() -> dict:
    path = config.MODULE_INDEX / "item_index.json"
    if not path.exists():
        raise SystemExit(
            f"{path} is missing. It is gitignored and built by the wiki refresh;\n"
            "run `nwn-manager wiki` once, or ask the admin to, before this task."
        )
    return {i["resref"]: i for i in json.loads(path.read_text())["items"]}


def selector() -> list[Item]:
    index = _index()
    items: list[Item] = []
    for path in sorted(config.UNPACKED.glob("*.uti.json")):
        resref = gff.resref_of(path)
        if resref.startswith(SKIP_PREFIX):
            continue
        data = gff.load(path)
        # Both description fields blank -- examining this shows nothing at all.
        if gff.read_loc(data, "DescIdentified") or gff.read_loc(data, "Description"):
            continue
        # Non-magical items are mostly stock junk; properties mean it is worth text.
        if not (data.get("PropertiesList", {}) or {}).get("value"):
            continue
        name = gff.read_loc(data, "LocalizedName")
        if not name:
            continue  # nothing to key a description off
        entry = index.get(resref)
        if not entry or not entry.get("accessible"):
            continue  # players cannot obtain it, so nobody will ever read this
        if entry.get("base_item") in SKIP_BASE:
            continue

        item = build_item(resref, data, entry)
        if item:
            items.append(item)
    return items


def build_item(resref: str, data: dict | None = None,
               entry: dict | None = None) -> Item | None:
    """Build the prompt Item for one resref, with no emptiness filtering.

    Split out of selector() so a re-roll can rebuild the prompt for an item that
    already has text -- see Task.item_builder.
    """
    path = config.UNPACKED / f"{resref}.uti.json"
    if not path.exists():
        return None
    if entry is None:
        entry = _index().get(resref)
    if not entry:
        return None
    if data is None:
        data = gff.load(path)
    name = gff.read_loc(data, "LocalizedName") or entry.get("name", "").strip()
    if not name:
        return None

    properties = wiki.item_properties(resref)
    lines = [f"Item name: {name}", f"Item type: {entry.get('base_item', 'unknown')}"]
    if properties:
        lines.append(f"Magical properties: {properties}")
    sources = entry.get("sources") or []
    if sources:
        lines.append("Found in the world: " + "; ".join(sources[:3]))
    return Item(key=resref, path=path, field=FIELD, context="\n".join(lines),
                before=None, extra={"name": name, "properties": properties})


TASK = Task(
    name="item_desc",
    description="Flavour text for obtainable magical items that have no description",
    risk="auto",
    system=SYSTEM,
    user_template=TEMPLATE,
    prompt_version=5,
    selector=selector,
    max_chars=300,
    min_chars=60,
    allow_digits=False,
    temperature=0.9,
    style_angles=ANGLES,
    item_builder=build_item,
    field=FIELD,
)
