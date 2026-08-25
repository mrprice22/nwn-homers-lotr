"""creature_desc -- Bestiary text for creatures that have none.

535 of 781 creature blueprints have an empty `Description`. That field is what
the examine pane and the Bestiary book show, so those creatures currently read
as blank entries in a system the module otherwise makes a feature of.

Risk tier `auto`: the selector only takes creatures whose Description is empty.

Context comes from module-index/creature_index.json, which has the resolved
name, race, CR, faction and appearance -- none of which is readable from the raw
.utc.json, where they are all numeric ids.
"""
from __future__ import annotations

import bisect
import json
import re

if __package__ in (None, ""):
    import pathlib as _pathlib
    import sys as _sys
    _sys.path.insert(0, str(_pathlib.Path(__file__).resolve().parents[2]))

from llm import config, gff
from llm.tasks.base import CONFIDENCE_NOTE, Item, Task

FIELD = "Description.value.0"

# Toolset scaffolding, DM tools and third-party systems -- not module creatures.
SKIP_PREFIX = ("dmfi_", "sd_appear", "nw_c_", "x2_", "ds_", "cbd_", "mw_test",
               "server_npc", "wp_", "_")
# Placeholder names that mean "this blueprint is scaffolding", surfaced by
# sampling the real data ("A Creator" is a debug spawner, not a creature).
SKIP_NAME = re.compile(
    r"^(a creator|test|tester|dummy|placeholder|npc|creature\d*|new .*|<.*>|\[.*\])$",
    re.I)

SYSTEM = f"""You write Bestiary entries for a Lord of the Rings themed Neverwinter Nights persistent world.

Rules, in order of importance:
1. Two or three sentences. Under 340 characters. Never longer.
2. Say what the creature looks like and how it fights. Those are the two things
   a player wants from a Bestiary entry.
3. NEVER quote statistics, levels, challenge ratings or numbers of any kind.
4. Do not invent named people or places. You may use Tolkien's own names and the
   names given to you in the prompt, and nothing else.
5. Plain ASCII punctuation. Use -- for a dash. No curly quotes, no ellipsis
   character. Do not wrap the text in quotation marks.
6. Tolkien's register: concrete and grim, not video-game epic. A high challenge
   rating means describe something formidable, never "level 60".
7. DO NOT INVENT ABILITIES. Describe what you were told -- its look, its race,
   how something built like that would fight -- and nothing beyond it. Do not
   give it breath weapons, spellcasting, poison, flight, invisibility or a gaze
   attack unless the information you were given says so. The NAME IS NOT
   EVIDENCE: a creature called "Flame Archer" whose description says it is a
   skeleton wreathed in green fire shoots arrows, it does not cast fireballs.
   Telling a player a monster does something it cannot gets them killed.
8. VARY YOUR LANGUAGE. Left to itself this model reaches for the same handful of
   words for every creature. These are MEASURED on a real batch of creature
   descriptions, not guessed: "heavy" appeared in eleven out of sixteen,
   "strikes" in seven, "stout" in seven. Do not use: heavy, strikes, stout,
   sickly, jagged, gaunt, hulking, wreathed, radiates, exudes, malice, primal.
   Vary the verb for attacking -- it lunges, hammers, darts, closes, looses,
   drives, batters -- and do not open every description the same way.

{CONFIDENCE_NOTE}"""

TEMPLATE = """{context}

{angle}

Write the Bestiary description for this creature."""

# Rotated deterministically per resref. The structural guard against a batch of
# 519 creatures all being described the same way -- detection alone only tells
# you afterwards that the work has to be thrown away.
ANGLES = (
    "Lead with what it looks like at a distance, before it closes.",
    "Lead with how it moves and carries itself.",
    "Lead with the single detail a survivor would remember.",
    "Lead with how it opens a fight.",
    "Lead with what it sounds or smells like.",
    "Lead with where it is found and what that place has made of it.",
)


def _index() -> dict:
    path = config.MODULE_INDEX / "creature_index.json"
    if not path.exists():
        raise SystemExit(
            f"{path} is missing. It is gitignored and built by the wiki refresh;\n"
            "run `nwn-manager wiki` once, or ask the admin to, before this task."
        )
    index = {}
    for entry in json.loads(path.read_text())["creatures"]:
        index.setdefault(entry["blueprint_resref"], entry)
    return index


_CR_SORTED: list[float] | None = None

# How threatening, in words. Absolute cutoffs were wrong for the same reason the
# item ranking was: they encode an assumption about the scale instead of reading
# it. This module's CR runs from 0.17 to 17427 with a median of 88, so fixed
# thresholds put 39% of every creature in the top band and "legendary terror"
# stopped meaning anything. These are percentiles of the module's own spread.
_THREAT_BANDS = (
    (0.97, "among the deadliest things in the world"),
    (0.85, "a legendary terror, a match for the greatest heroes"),
    (0.65, "a formidable foe, dangerous to a seasoned company"),
    (0.35, "a real but manageable threat"),
    (0.12, "a modest threat to an experienced traveller"),
    (0.00, "a minor threat, easily handled"),
)


def _cr_distribution() -> list[float]:
    global _CR_SORTED
    if _CR_SORTED is None:
        values = []
        for entry in _index().values():
            try:
                values.append(float(entry.get("cr")))
            except (TypeError, ValueError):
                pass
        _CR_SORTED = sorted(values)
    return _CR_SORTED


def _threat(cr: str | float | None) -> str:
    """CR as a word, ranked against every other creature in the module."""
    try:
        value = float(cr)
    except (TypeError, ValueError):
        return "unknown"
    series = _cr_distribution()
    if not series:
        return "unknown"
    pct = bisect.bisect_right(series, value) / len(series)
    for threshold, phrase in _THREAT_BANDS:
        if pct >= threshold:
            return phrase
    return _THREAT_BANDS[-1][1]


def selector() -> list[Item]:
    index = _index()
    items: list[Item] = []
    for path in sorted(config.UNPACKED.glob("*.utc.json")):
        resref = gff.resref_of(path)
        if resref.startswith(SKIP_PREFIX):
            continue
        data = gff.load(path)
        if gff.read_loc(data, "Description"):
            continue
        entry = index.get(resref)
        if not entry:
            continue
        name = (entry.get("name") or "").strip()
        if not name or SKIP_NAME.match(name):
            continue

        item = build_item(resref, data, entry)
        if item:
            items.append(item)
    return items


def build_item(resref: str, data: dict | None = None,
               entry: dict | None = None) -> Item | None:
    """Build the prompt Item for one resref, with no emptiness filtering.

    Split out of selector() so a re-roll can rebuild the prompt for a creature
    that already has a description -- see Task.item_builder.
    """
    path = config.UNPACKED / f"{resref}.utc.json"
    if not path.exists():
        return None
    if entry is None:
        entry = _index().get(resref)
    if not entry:
        return None
    if data is None:
        data = gff.load(path)
    name = (entry.get("name") or "").strip()
    if not name:
        return None

    lines = [f"Creature name: {name}"]
    if entry.get("race"):
        lines.append(f"Race: {entry['race']}")
    if entry.get("appearance_name"):
        lines.append(f"Looks like: {entry['appearance_name']}")
    if entry.get("faction_name"):
        lines.append(f"Faction: {entry['faction_name']}")
    lines.append(f"Threat level: {_threat(entry.get('cr'))}")
    locations = entry.get("locations") or []
    if locations:
        names = [loc.get("area_name", loc) if isinstance(loc, dict) else str(loc)
                 for loc in locations[:3]]
        lines.append("Found in: " + "; ".join(str(n) for n in names))
    return Item(key=resref, path=path, field=FIELD,
                context="\n".join(lines), before=None,
                extra={"name": name})


TASK = Task(
    name="creature_desc",
    description="Bestiary text for creature blueprints with no description",
    risk="auto",
    system=SYSTEM,
    user_template=TEMPLATE,
    prompt_version=3,
    selector=selector,
    max_chars=340,
    min_chars=60,
    allow_digits=False,
    temperature=0.9,
    style_angles=ANGLES,
    item_builder=build_item,
    field=FIELD,
)
