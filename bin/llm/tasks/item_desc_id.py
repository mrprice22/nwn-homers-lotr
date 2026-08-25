"""item_desc_id -- the identified description, written with the item's real standing.

Round one (`item_desc`) wrote physical description under a hard "no mechanics,
no numbers" rule, and that text now lives in the unidentified slot where it
belongs. This is the other half: the text a player sees *after* identifying,
which may speak to what the thing actually does.

The difference that matters is not more words, it is **scale**. Round one had the
property list and was told to ignore it, so a bracer granting the highest
Strength bonus in the world read exactly like one granting the lowest. Here every
property arrives already ranked against every other item of its kind in this
module (`llm/itemstats.py`), so "+12" comes through as *nothing in the world
grants more* and "+1" as *slight*.

Risk tier `auto`: the selector only takes items whose identified slot is empty.
"""
from __future__ import annotations

import json

if __package__ in (None, ""):
    import pathlib as _pathlib
    import sys as _sys
    _sys.path.insert(0, str(_pathlib.Path(__file__).resolve().parents[2]))

from llm import config, gff, itemstats
from llm.tasks.base import CONFIDENCE_NOTE, Item, Task
from llm.tasks.item_desc import SKIP_BASE, SKIP_PREFIX

FIELD = "DescIdentified.value.0"

SYSTEM = f"""You write the identified description for items in a Lord of the Rings themed Neverwinter Nights persistent world.

The player has already identified this item and can see its statistics on a list
beside your text. Your job is the character of the thing, not its numbers.

Rules, in order of importance:
1. One to three sentences. Under 340 characters. Never longer.
2. You MAY allude to what the item does -- "the wearer's words come easier",
   "cold death answers its call", "wounds close before they are felt". Say what
   it is like to carry, not what it grants.
3. NEVER quantify. No numbers, no skill names, no property names, no "+" values,
   no percentages, no "per day". Those are on the list already; repeating them
   wastes the only space you have.
4. MATCH THE REGISTER TO THE STANDING. Each property is marked with how it ranks
   against every other item of its kind in this world. Something marked "nothing
   in the world grants more" should read as a thing of legend. Something marked
   "slight" or "modest" should read as a decent, ordinary piece -- do not inflate
   it. Getting this wrong in either direction is the main way to fail this task.
5. Do not invent named people or places. Use Tolkien's own names and the names
   you are given, nothing else. Where the item is found in the world is given to
   you -- use it rather than imagining a provenance.
6. Plain ASCII punctuation. Use -- for a dash. No curly quotes, no ellipsis
   character. Do not wrap the description in quotation marks.
7. Tolkien's register: concrete, weathered, unshowy. Not video-game epic.
8. VARY YOUR LANGUAGE. Left alone you reach for the same words for every item;
   measured over a real batch, one adjective appeared in fifteen descriptions out
   of sixteen. Avoid: heavy, weighty, feels, unnaturally, seems to, thrums,
   hums with, to the touch. Do not open every description the same way.
9. Do NOT lean on the word "wearer" -- in a measured batch it appeared in eleven
   descriptions out of twenty and opened four of them. Name the person if the
   item's provenance gives you one, write "the one who carries it", or put the
   sentence on the object's side instead. Never open with "The wearer" or
   "Forged for". Nor "steady" -- it reached seven descriptions in twenty once
   "wearer" was taken away.
10. DO NOT CLAIM A CAPABILITY THE ITEM DOES NOT HAVE. Describe how it looks,
   feels, was made and was used as freely as you like. But do not say it makes
   the bearer quiet, quick, hidden, healed or sharp-eyed unless a property in
   the list above grants that. The NAME IS NOT EVIDENCE -- boots called "of the
   Mirkwood Elf" are not stealthy unless the properties say they are, and
   writing that they are tells the player something false about their own gear.

{CONFIDENCE_NOTE}"""

TEMPLATE = """{context}

{angle}

Write the identified description for this item."""

# Rotated deterministically per resref -- see Task.angle(). Prevents the batch
# converging on one shape, which detection alone can only report after the fact.
ANGLES = (
    "Lead with what the item does for the one who carries it.",
    "Lead with who made it, or who it was made for.",
    "Lead with a physical detail that betrays its power.",
    "Lead with what it has already been used for.",
    "Lead with how it changes the bearer's bearing or mood.",
)


def _index() -> dict:
    path = config.MODULE_INDEX / "item_index.json"
    if not path.exists():
        raise SystemExit(
            f"{path} is missing. It is gitignored and built by the wiki refresh;\n"
            "run `nwn-manager wiki` once, or ask the admin to, before this task."
        )
    return {i["resref"]: i for i in json.loads(path.read_text())["items"]}


def build_item(resref: str, data: dict | None = None,
               entry: dict | None = None) -> Item | None:
    """Build the prompt Item for one resref, with no "is it empty" filtering.

    Split out of selector() so a re-roll can rebuild the prompt for an item
    whose field is already filled -- which every item is, once it has been
    generated once.
    """
    path = config.UNPACKED / f"{resref}.uti.json"
    if not path.exists():
        return None
    if data is None:
        data = gff.load(path)
    if entry is None:
        entry = _index().get(resref)
    if not entry:
        return None

    brief = itemstats.item_brief(resref, entry)
    context = itemstats.brief_text(brief)
    # The unidentified line is what the player already read; giving it to the
    # model stops the identified text repeating the same physical details.
    unidentified = gff.read_loc(data, "Description")
    if unidentified:
        context += ("\n\nWhat the player saw before identifying it (do not repeat "
                    "these details):\n" + unidentified)
    return Item(key=resref, path=path, field=FIELD, context=context,
                before=None, extra={"name": brief["name"],
                                    "tier": brief["overall_tier"],
                                    "properties": "; ".join(brief["properties"])})


def selector() -> list[Item]:
    index = _index()
    items: list[Item] = []
    for path in sorted(config.UNPACKED.glob("*.uti.json")):
        resref = gff.resref_of(path)
        if resref.startswith(SKIP_PREFIX):
            continue
        data = gff.load(path)
        if gff.read_loc(data, "DescIdentified"):
            continue                       # already has identified text
        if not gff.read_loc(data, "Description"):
            continue                       # nothing to build on
        if not (data.get("PropertiesList", {}) or {}).get("value"):
            continue
        entry = index.get(resref)
        if not entry or not entry.get("accessible"):
            continue                       # players cannot obtain it
        if entry.get("base_item") in SKIP_BASE:
            continue
        item = build_item(resref, data, entry)
        if item:
            items.append(item)
    return items


TASK = Task(
    name="item_desc_id",
    description="Identified description, written to the item's real standing in the world",
    risk="auto",
    system=SYSTEM,
    user_template=TEMPLATE,
    prompt_version=4,
    selector=selector,
    max_chars=340,
    min_chars=60,
    allow_digits=False,
    temperature=0.9,
    style_angles=ANGLES,
    item_builder=build_item,
    field=FIELD,
)
