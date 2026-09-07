#!/usr/bin/env python3
"""Give the Weathertop Royal Magus its level 8/9 book (roadmap: wtop-court-combat-defects).

The Magus is Wizard 60 / Undead 60 / Dragon Disciple 60 and reads as an archmage,
but its offensive arsenal topped out at Magic Missile x99 and Vampiric Touch x99:
players reported it as a damage sponge that barely fought back. This script owns
the fix -- the level 8 and 9 list on wtop_crtmage's SpecAbilityList.

WHY A SCRIPT AND NOT A HAND EDIT. SpecAbilityList is one struct per USE, so
"twelve Meteor Swarms" is twelve near-identical JSON blocks and the list runs to
several hundred entries. Hand-editing that is unreviewable and unrepeatable; a
table is neither.

WHY SpecAbilityList AND NOT KnownList. It is what every other boss caster in this
module uses -- gandalf001 and sarumanthewhi001 both carry their epic spells this
way, on stock AI -- and the stock AI's DetermineCombatRound picks talents from it
with no further wiring. weathertopque003 already carries 577 uses across 53
spells, so the totals below are in band for this tier.

WHAT IS DELIBERATELY *NOT* HERE. Greater Ruin, Mordenkainen's Disjunction and
Mummy Dust are cast from unpacked/wtop_cmage.nss instead, on a COURT-WIDE
60-second cooldown. An AI-chosen talent cannot be rate-limited, and the court
fields several Magi: left in this list, a party walking onto the middle level ate
every one of them at once. The script strips those three ids from the blueprint
for that reason -- Disjunction was in it.

Idempotent: every id it owns is removed and rewritten from the table, so running
it twice produces the same file. Dry run by default; --apply writes.
"""
from __future__ import annotations

import argparse
import json
import sys
from collections import Counter, OrderedDict
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
BLUEPRINT = ROOT / "unpacked" / "wtop_crtmage.utc.json"

# Caster level stamped on every owned entry. The existing entries say 1, which
# caps damage and duration at a first-level caster's numbers -- Horrid Wilting
# alone loses most of its dice to that. 60 is the Magus's own wizard level.
CASTER_LEVEL = 60
SPELL_FLAGS = 1  # what every other entry on this blueprint and the Queen's uses

# spell id -> uses.  ids are spells.2da rows (SPELL_* in nwscript.nss).
BOOK = OrderedDict([
    # --- level 9: the ones that end an encounter -------------------------
    (190, 12),   # Wail of the Banshee
    (193, 12),   # Weird
    (116, 12),   # Meteor Swarm
    (131, 12),   # Power Word Kill
    (51,  12),   # Energy Drain
    (44,   8),   # Dominate Monster
    (63,   8),   # Gate
    (533,  8),   # Black Blade of Disaster
    (178,  8),   # Summon Creature IX
    (185,  4),   # Time Stop
    # --- level 8 ---------------------------------------------------------
    (367, 12),   # Horrid Wilting
    (89,  12),   # Incendiary Cloud
    (427, 10),   # Sunburst
    (423, 10),   # Bombardment
    (110, 10),   # Mass Blindness and Deafness
    (111,  8),   # Mass Charm
    (134,  8),   # Premonition (self-defence, so it survives to cast the rest)
    (117,  4),   # Mind Blank
])

# Cast from wtop_cmage.nss on a court-wide cooldown -- never from the AI's list.
SCRIPTED = OrderedDict([
    (640, "Greater Ruin"),
    (122, "Mordenkainen's Disjunction"),
    (637, "Epic Mummy Dust"),
])


def entry(spell_id: int) -> dict:
    return {
        "__struct_id": 4,
        "Spell": {"type": "word", "value": spell_id},
        "SpellCasterLevel": {"type": "byte", "value": CASTER_LEVEL},
        "SpellFlags": {"type": "byte", "value": SPELL_FLAGS},
    }


def main() -> int:
    ap = argparse.ArgumentParser(description=__doc__,
                                 formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--apply", action="store_true",
                    help="write the blueprint (default: report only)")
    args = ap.parse_args()

    if not BLUEPRINT.exists():
        print(f"error: {BLUEPRINT} not found", file=sys.stderr)
        return 1

    data = json.loads(BLUEPRINT.read_text(encoding="utf-8"))
    old = data.get("SpecAbilityList", {}).get("value", [])
    before = Counter(e["Spell"]["value"] for e in old)

    owned = set(BOOK) | set(SCRIPTED)
    kept = [e for e in old if e["Spell"]["value"] not in owned]
    new = kept + [entry(sid) for sid, uses in BOOK.items() for _ in range(uses)]

    after = Counter(e["Spell"]["value"] for e in new)

    print(f"wtop_crtmage SpecAbilityList: {len(old)} -> {len(new)} uses "
          f"({len(before)} -> {len(after)} distinct spells)")
    for sid, uses in BOOK.items():
        was = before.get(sid, 0)
        print(f"  book     spell {sid:>4}: {was:>3} -> {uses:>3}"
              + ("  (unchanged)" if was == uses else ""))
    for sid, name in SCRIPTED.items():
        was = before.get(sid, 0)
        print(f"  scripted spell {sid:>4}: {was:>3} -> {0:>3}   {name} "
              f"-- cast from wtop_cmage.nss on the court cooldown")

    if new == old:
        print("blueprint already matches the table; nothing to do")
        return 0
    if not args.apply:
        print("dry run -- pass --apply to write")
        return 0

    data["SpecAbilityList"]["value"] = new
    BLUEPRINT.write_text(json.dumps(data, indent=2) + "\n", encoding="utf-8")
    print(f"wrote {BLUEPRINT.relative_to(ROOT)}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
