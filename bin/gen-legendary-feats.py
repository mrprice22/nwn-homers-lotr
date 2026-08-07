#!/usr/bin/env python3
"""gen-legendary-feats.py - own the legendary feat rows in hak_2da/feat.2da.

Phase 2 of the Legendary Feats build order (CLAUDE-legendary-feats.md).

THE ARCHITECTURE, IN ONE LINE
-----------------------------
**A legendary feat row carries name, description and icon only.** It has no
engine mechanic. Every effect is applied server-side by script — ability bonuses
as item properties on the PC's skin, other effects as permanent supernatural
effects re-applied at login, spell changes as a branch on GetHasFeat(). That is
what makes "NWN can't express that in a 2DA" entries tractable, and it means
**feat.2da gates nothing**: prerequisites, class restrictions and the level-60
allotment all live in the picker (phase 3), in script, where they can be
arbitrarily expressive.

THE EASIEST BUG TO SHIP
-----------------------
**The engine must never offer a legendary feat on its own level-up feat page.**
The picker is the only grant path; a feat reachable from both is a double-grant.
Every row here therefore sets `ALLCLASSESCANUSE = 0` and is listed in no
`cls_feat_*.2da`, which is what keeps it off every class's selection list.
tests/check_legendary_feats.py asserts that column on every owned row.

THE BASE TABLE
--------------
The module resolves the **stock** feat.2da: **1116 rows (0-1115, last
PLAYER_TOOL_10) and 43 columns**. It does NOT resolve hak_2da/feat.2da's former
contents, which were a byte-identical copy of the table inside
`cep2_add_feats.hak` — **a hak Mod_HakList does not load** (24,771 rows, 44
columns). Building on that copy would have silently added ~23,000 CEP
weapon-of-choice feats and changed the column count. It was a reference extract
and is recoverable from cep2_add_feats.hak if it is ever wanted again.

So: **our rows append at 1116**, rows 0-1115 stay byte-identical, and the gate
asserts both. Re-extracting feat.2da from the game data over the generated file
silently drops every legendary row — seed a fresh base with --from-stock
instead, which preserves our rows and swaps only the base underneath them.

SINGLE SOURCE OF TRUTH
----------------------
FEATS below drives both the 2DA rows and the TLK strings: bin/build-lotr-tlk
imports `tlk_strings()` from this module and appends them to its own block, so a
feat name is typed exactly once. The strref each row points at is derived from
where build-lotr-tlk actually places that string, not from a number written down
twice.

Usage:
    python3 bin/gen-legendary-feats.py                    # dry run
    python3 bin/gen-legendary-feats.py --apply            # write hak_2da/feat.2da
    python3 bin/gen-legendary-feats.py --apply --from-stock /tmp/feat.2da
                                                          # ... reseeding the base

Extract a fresh stock base with (see README.md "Rebuild from scratch"):
    NWN="$HOME/.local/share/Steam/steamapps/common/Neverwinter Nights"
    ~/.nimble/bin/nwn_resman_cat --root "$NWN" \\
      --userdirectory "$HOME/.local/share/Neverwinter Nights" feat.2da > /tmp/feat.2da

Idempotent: a second --apply run reports no changes. Publishing needs the hak
AND the TLK, because the rows point at strrefs that only exist in ours:

    bin/build-lotr-tlk --apply --install
    python3 bin/gen-legendary-feats.py --apply
    bin/build-lotr-rules-hak --install
    bin/refresh-nwsync
    nwn-manager repack
    bin/server-restart
"""
import argparse
import importlib.machinery
import importlib.util
import sys
from dataclasses import dataclass
from pathlib import Path

REPO = Path(__file__).resolve().parent.parent
FEAT_2DA = REPO / "hak_2da" / "feat.2da"
TLK_GENERATOR = REPO / "bin" / "build-lotr-tlk"
# Generated: the script-side view of the same table. Scripts must never hand-type
# a feat row number — a renumbered row would silently become a different feat.
IDS_INC = REPO / "unpacked" / "legfeat_ids_inc.nss"

# The stock table's shape. Both are asserted before anything is written: a base
# with a different row count or column count is not the table the module
# resolves, and appending to it would put our rows at the wrong feat IDs.
BASE_ROWS = 1116               # stock rows 0..1115
BASE_COLUMNS = 43              # header columns, excluding the row-index column
FIRST_ROW = BASE_ROWS          # our first feat ID

BLANK = "****"


@dataclass(frozen=True)
class Req:
    """One prerequisite clause.

    A prerequisite used to be two independent hand-typed strings - an NWScript
    expression and a display string - with nothing checking that the second
    described the first. Roadmap item legendary-feat-prereq-defect-1 is what that
    cost: a player at BAB 35 who lacked Epic Prowess saw the whole requirement
    ("Requires: BAB 35+, Epic Prowess") greyed out with no way to tell WHICH half
    had failed, and reported it as "35 is not being accepted". Clauses exist so
    the comparison, the display text and the player's own measured value all come
    out of ONE declaration.

    `minimum is None` -> BOOLEAN clause. `expr` is the whole test; `label` is how
        the picker names it ("Epic Prowess"). Nothing is measured to show.
    `minimum` set     -> NUMERIC clause. `expr` yields a value; the generator
        emits `(expr) >= minimum` and the text "<label> <minimum>+ <unit>", and
        the picker shows the player's evaluated `expr` beside it.

    A numeric clause CANNOT express `>` - the operator is generated, not typed.
    That is the general ask on legendary-feat-prereq-defect-1 ("any X value
    requirement should be >=, not >") made structural rather than conventional,
    and tests/check_legendary_feats.py asserts it on the generated output.

    Read BASE ability scores (GetAbilityScore(..., TRUE)) and not the buffed
    ones: a prerequisite met by swapping on a +12 belt for the duration of one
    button press is not a prerequisite.
    """
    label: str
    expr: str
    minimum: int | None = None
    unit: str = ""             # "ranks" on skill clauses; "" everywhere else

    @property
    def is_numeric(self) -> bool:
        return self.minimum is not None

    def nss_test(self) -> str:
        """The NWScript boolean test for this clause."""
        if not self.is_numeric:
            return self.expr
        return f"({self.expr}) >= {self.minimum}"

    def text(self) -> str:
        """How the picker names this clause when it is not showing a value."""
        if not self.is_numeric:
            return self.label
        s = f"{self.label} {self.minimum}+"
        return f"{s} {self.unit}" if self.unit else s


def REQ_BAB(minimum: int) -> Req:
    """The BAB clause, spelled once.

    A BAB prerequisite below ~30 is decorative at this level cap: levels 21-60
    grant +1 BAB every 2 levels, so every level-60 character clears 20. A martial
    prerequisite that means anything is 30+ or 35+ — a pure level-60 Fighter
    reaches 40, a pure 3/4-BAB class reaches exactly 35, and what separates
    builds is levels 1-20.

    Note this is BASE attack bonus, not the character sheet's total. The label
    says "BAB" for that reason, and the picker now prints the measured number
    beside it so the two can never be confused again.
    """
    return Req("BAB", "GetBaseAttackBonus(oPC)", minimum)


@dataclass
class Feat:
    """One legendary feat. `effect` is documentation for now - phase 3's picker
    and the per-category behaviour scripts are what read it."""
    label: str                 # 2DA LABEL and nwscript Constant (minus FEAT_)
    name: str                  # TLK string, shown in the feat list
    description: str           # TLK string, shown in the tooltip
    icon: str                  # existing icon resref; we ship no new art yet
    effect: str = ""           # human-readable summary of what the script does
    category: str = ""         # draft section this came from
    # Ability-score feats only: the ABILITY_* constant this boosts and by how
    # much. Generated into legfeat_ids_inc.nss so the picker applies the bonus
    # from the same table that names the feat. -1 = not an ability feat.
    ability: int = -1
    bonus: int = 0
    # How the effect is applied. "raw_ability" writes the character's BASE
    # ability score (NWNX_Creature_SetRawAbilityScore, the Akira's Mixtape
    # route): permanent, saved in the .bic, applied exactly once and never
    # re-applied at login. "effect" is a permanent supernatural effect rebuilt
    # on every login. Getting this wrong on a raw_ability feat stacks another
    # +6 into the .bic every session, silently and permanently.
    #
    # "hook" is the third kind: the feat grants NOTHING at pick time or at
    # login. It is a pure token that some combat hook elsewhere reads with
    # GetHasFeat — Legendary Butcher, read by unpacked/devcrit_atk.nss, is the
    # first. LegFeat_ApplyAll must leave these alone; applying an effect for one
    # would double the benefit.
    kind: str = "effect"
    # Prerequisite, as a tuple of Req clauses ANDed together. Empty = no
    # prerequisite. The picker greys a row whose clauses do not all pass and
    # LegFeat_Take refuses it, so this is the ONLY place a prerequisite is
    # written down — feat.2da gates nothing (see the architecture note at the
    # top of this file). See Req above for the clause forms and why the
    # comparison operator is generated rather than typed.
    reqs: tuple[Req, ...] = ()


# ---------------------------------------------------------------------------
# The feat table. APPEND ONLY, for the same reason bin/build-lotr-tlk's string
# table is: a feat's row index is its FEAT_* id, baked into save games the
# moment a character takes it, and its strings sit at a fixed TLK index.
# Inserting or removing an entry renumbers every feat after it and silently
# turns granted feats into different feats.
# ---------------------------------------------------------------------------
FEATS: list[Feat] = [
    Feat("LEGENDARY_STRENGTH", "Legendary Strength",
         "Your might has passed out of the merely mortal. You gain a permanent "
         "+6 bonus to Strength.",
         "ife_X2GrStr1", effect="+6 Strength (base)",
         category="Ability Scores", ability=0, bonus=6, kind="raw_ability"),
    Feat("LEGENDARY_DEXTERITY", "Legendary Dexterity",
         "You move as the wind through grass. You gain a permanent +6 bonus to "
         "Dexterity.",
         "ife_X2GrDex1", effect="+6 Dexterity (base)",
         category="Ability Scores", ability=1, bonus=6, kind="raw_ability"),
    Feat("LEGENDARY_CONSTITUTION", "Legendary Constitution",
         "Hurt cannot find purchase in you. You gain a permanent +6 bonus to "
         "Constitution.",
         "ife_X2GrCon1", effect="+6 Constitution (base)",
         category="Ability Scores", ability=2, bonus=6, kind="raw_ability"),
    Feat("LEGENDARY_INTELLIGENCE", "Legendary Intelligence",
         "Lore long lost lies open to you. You gain a permanent +6 bonus to "
         "Intelligence.",
         "ife_X2GrInt1", effect="+6 Intelligence (base)",
         category="Ability Scores", ability=3, bonus=6, kind="raw_ability"),
    Feat("LEGENDARY_WISDOM", "Legendary Wisdom",
         "You see the shape of things as they truly are. You gain a permanent "
         "+6 bonus to Wisdom.",
         "ife_X2GrWis1", effect="+6 Wisdom (base)",
         category="Ability Scores", ability=4, bonus=6, kind="raw_ability"),
    Feat("LEGENDARY_CHARISMA", "Legendary Charisma",
         "Others follow where you lead, and are glad of it. You gain a "
         "permanent +6 bonus to Charisma.",
         "ife_X2GrCha1", effect="+6 Charisma (base)",
         category="Ability Scores", ability=5, bonus=6, kind="raw_ability"),

    # --- Martial (ll-feats-ability-martial) -------------------------------
    # The first two LEGFEAT_KIND_EFFECT feats in the pool, and deliberately the
    # two simplest in the whole draft: one permanent supernatural effect each,
    # applied by a branch in LegFeat_ApplyOne and rebuilt at every login by
    # LegFeat_ApplyAll. Everything else martial needs a combat hook, a spell
    # script or an engine behaviour that is not scriptable — see
    # CLAUDE-legendary-feats-triage.md for the route each one takes.
    # On why the BAB thresholds sit where they do, see REQ_BAB above.
    Feat("LEGENDARY_PROWESS", "Legendary Prowess",
         "Every blow you aim finds its mark. You gain a permanent +5 bonus to "
         "your attack rolls.",
         "ife_X2EpicProw", effect="+5 attack bonus",
         category="Martial",
         # 35 is exactly what a pure 3/4-BAB level-60 character has (stock
         # cls_atk_2 row 59), so this gate is cleared by a hair or not at all —
         # which is precisely why the SECOND clause has to be visible. See
         # roadmap legendary-feat-prereq-defect-1.
         reqs=(REQ_BAB(35),
               Req("Epic Prowess", "GetHasFeat(FEAT_EPIC_PROWESS, oPC)"))),
    # Melee counterpart to Legendary Marksman: the extra attack is CONDITIONAL on
    # what is in hand, so it is applied and dropped by the equip hook
    # (legfeat_equip.nss) rather than sitting there permanently. Unarmed counts as
    # melee — the only thing that switches it off is holding a ranged weapon.
    Feat("LEGENDARY_ONSLAUGHT", "Legendary Onslaught",
         "You strike faster than the eye can follow. You gain one additional "
         "attack each round while fighting with a melee weapon or unarmed.",
         "ife_X2BldSpd", effect="+1 melee attack per round",
         category="Martial",
         # Monk level, not Flurry of Blows. Flurry is monk-only, so gating on it
         # said "monk" without saying it — and a prerequisite the player has to
         # reverse-engineer is a prerequisite they will misread. A CLASS LEVEL
         # is not a purity test: a 30/30 monk/rogue qualifies, which is intended.
         reqs=(REQ_BAB(30),
               Req("Monk level", "GetLevelByClass(CLASS_TYPE_MONK, oPC)", 30))),
    # The first LEGFEAT_KIND_HOOK feat: it applies nothing and is never rebuilt
    # at login. unpacked/devcrit_atk.nss reads GetHasFeat in the NWNX Damage
    # attack event and does all the work, which is also the only place a
    # critical hit is visible to script at all.
    #
    # Half of roadmap item devcrit-roll, and meaningless without it: that item
    # reworks the STOCK Devastating Critical from save-or-die into +3 dice of
    # the same size-scaled physical damage, and Butcher stacks +5 more on top.
    # A large weapon in the hands of someone with both lands +8d10. Butcher
    # additionally fires on an ORDINARY critical (attack result 3), which is
    # what makes it a critical-damage feat rather than a second dev-crit feat.
    #
    # Typed physical on purpose, so heavy damage reduction eats part of it.
    Feat("LEGENDARY_BUTCHER", "Legendary Butcher",
         "You do not wound; you ruin. Whenever you score a critical hit you "
         "deal 5 extra dice of damage, scaled to your weapon: d6 for a small "
         "weapon, d8 for a medium one, d10 for a large one. This is added to "
         "the extra damage of a devastating critical, not in place of it.",
         # Great Cleave's icon — already referenced by feat.2da, so it is known
         # to resolve. We ship no new art yet.
         "ife_X1GCleave", effect="+5 damage dice on a critical",
         category="Martial", kind="hook",
         reqs=(Req("Devastating Critical (any weapon)",
                   "LegFeat_HasAnyDevCrit(oPC)"),)),

    # --- Martial replacement set (approved 2026-08-03) --------------------
    # The reviewed replacements for the six martial feats the engine owns and
    # will not give up, plus the ranged and party-support ground the draft had
    # nothing on. Numbers and prerequisites are the admin's revised table in
    # CLAUDE-legendary-feats-triage.md ("Martial replacements"), signed off
    # 2026-08-03. Two entries of that table are NOT here - Legendary Warcry and
    # Legendary Called Shot - because each has a live design problem; see the
    # "Deferred" note under the table in the triage doc.
    #
    # Three kinds are represented, and the kind is the whole contract:
    #   effect      - a permanent supernatural effect, rebuilt at login.
    #   effect + conditional - same, but LegFeat_ApplyOne asks what is in hand,
    #                 so legfeat_equip.nss must rebuild it on every weapon swap.
    #   hook        - grants NOTHING here; a combat hook reads GetHasFeat.
    #                 Giving one a case in LegFeat_ApplyOne pays it out twice.
    Feat("LEGENDARY_JUGGERNAUT", "Legendary Juggernaut",
         "Nothing moves you that you do not choose to be moved by. You are "
         "immune to knockdown, entanglement, paralysis and slow, and your "
         "weapon cannot be struck from your hand.",
         "ife_knockdow", effect="immune to knockdown, entangle, paralysis, "
                                "slow and disarm",
         category="Martial",
         # Discipline is read as BASE ranks: a Discipline requirement met by a
         # +10 skill cloak is met by taking the cloak off again.
         reqs=(REQ_BAB(20),
               Req("Discipline", "GetSkillRank(SKILL_DISCIPLINE, oPC, TRUE)",
                   30, "ranks"))),
    # CONDITIONAL, like Onslaught: a weapon in each hand. Dropping the off-hand
    # must drop the bonus, which is legfeat_equip.nss's job.
    Feat("LEGENDARY_GRIP", "Legendary Grip",
         "Two blades, one will. While you fight with a weapon in each hand you "
         "gain +4 to your attack rolls and +6 to your Armour Class.",
         "ife_twoweap", effect="+4 attack, +6 AC while dual-wielding",
         category="Martial",
         reqs=(Req("Ambidexterity", "GetHasFeat(FEAT_AMBIDEXTERITY, oPC)"),
               Req("Improved Two-Weapon Fighting",
                   "GetHasFeat(FEAT_IMPROVED_TWO_WEAPON_FIGHTING, oPC)"),
               Req("Weapon Finesse", "GetHasFeat(FEAT_WEAPON_FINESSE, oPC)"))),
    # CONDITIONAL, and the ranged counterpart to Legendary Onslaught. Bows and
    # crossbows only - not slings, not thrown - so it cannot be held alongside
    # Onslaught's melee attack by holding one of each.
    Feat("LEGENDARY_MARKSMAN", "Legendary Marksman",
         "Your shots come faster than an archer's eye can follow. You gain one "
         "additional attack each round while wielding a bow or a crossbow.",
         "ife_rapidshot", effect="+1 ranged attack per round (bow/crossbow)",
         category="Martial",
         reqs=(Req("Rapid Shot", "GetHasFeat(FEAT_RAPID_SHOT, oPC)"),
               Req("Point Blank Shot", "GetHasFeat(FEAT_POINT_BLANK_SHOT, oPC)"),
               REQ_BAB(30))),
    # HOOK (defender side): legfeat_dmg.nss, the NWNX Damage event script that
    # LegFeat_ArmHooks registers on the character. Reduction happens AFTER the
    # engine has finished with damage reduction, resistance and immunity, which
    # is the whole point - it is the only layer that cannot be resisted around.
    Feat("LEGENDARY_BULWARK", "Legendary Bulwark",
         "The shield is not a thing you carry; it is a thing you are. While a "
         "shield is on your arm, every blow that reaches you is reduced by 10 "
         "points, after all other reductions and resistances.",
         "ife_sh_prof", effect="-10 damage taken while a shield is equipped",
         category="Martial", kind="hook",
         reqs=(Req("Shield Proficiency",
                   "GetHasFeat(FEAT_SHIELD_PROFICIENCY, oPC)"),
               REQ_BAB(15))),
    # HOOK (defender side), same script as Bulwark.
    #
    # 60 RANKS of Parry, not 60 modified Parry: at this level cap the modified
    # number is mostly gear. Ranks are what the character spent.
    Feat("LEGENDARY_RIPOSTE", "Legendary Riposte",
         "You answer the blade with the blade. Once each round, when a melee "
         "attack lands on you, you may turn it aside and strike back for your "
         "weapon's damage. You do not stop attacking to do it.",
         "ife_impparry", effect="1/round counter-attack when hit in melee",
         category="Martial", kind="hook",
         reqs=(Req("Parry", "GetSkillRank(SKILL_PARRY, oPC, TRUE)",
                   60, "ranks"),)),
    # HOOK (attacker side): legfeat_atk_inc.nss, called from devcrit_atk.nss.
    Feat("LEGENDARY_REAPING", "Legendary Reaping",
         "Killing feeds you. Each enemy you fell grants +2 to your attack rolls "
         "and +2 damage for 12 seconds, stacking up to five times.",
         "ife_cleave", effect="+2 attack/+2 damage per kill, 12s, stacks 5",
         category="Martial", kind="hook",
         reqs=(Req("Great Cleave", "GetHasFeat(FEAT_GREAT_CLEAVE, oPC)"),
               REQ_BAB(35))),
    # HOOK (attacker side). Scales off the attacker's OWN missing health, so it
    # is at its best exactly when the character is closest to dying.
    Feat("LEGENDARY_WRATH", "Legendary Wrath",
         "Wound you and you only grow terrible. Your blows deal +1 damage for "
         "every 5% of your health that is missing, up to +20.",
         "ife_rage", effect="+1 damage per 5% health missing, max +20",
         category="Martial", kind="hook",
         # CON is read as the BASE score for the usual reason - a belt is not a
         # constitution.
         reqs=(Req("Constitution",
                   "GetAbilityScore(oPC, ABILITY_CONSTITUTION, TRUE)",
                   21, "(base)"),)),
    # HOOK (attacker side). The only feat in the pool that reads the target's
    # race, and the only one that pays off a class's own mechanic.
    Feat("LEGENDARY_QUARRY", "Legendary Quarry",
         "You finish what you have hunted. Against a favoured enemy that has "
         "fallen below half its health, you deal half again as much damage.",
         "ife_trackstep", effect="+50% damage to favoured enemies below 50% HP",
         category="Martial", kind="hook",
         # A class level, not a purity test: a 30/30 ranger/rogue qualifies.
         reqs=(Req("Ranger level", "GetLevelByClass(CLASS_TYPE_RANGER, oPC)",
                   30),)),
    # HOOK (attacker side). The cap is the good part of the design: the armour
    # a target is actually wearing is the most it can be stripped of, so this
    # cannot shred an unarmoured or naturally-armoured enemy to nothing.
    Feat("LEGENDARY_SUNDERING", "Legendary Sundering",
         "You do not merely strike armour; you ruin it. Your landed attacks cut "
         "3 from your target's Armour Class, stacking three times, but never by "
         "more than the armour and shield it is actually wearing are worth.",
         "ife_disarm", effect="-3 target AC per hit, stacks 3, capped at its "
                              "armour+shield AC",
         category="Martial", kind="hook",
         reqs=(REQ_BAB(35),
               Req("Called Shot", "GetHasFeat(FEAT_CALLED_SHOT, oPC)"))),
]


def tlk_strings():
    """The strings bin/build-lotr-tlk appends to its block, in index order.

    Two per feat, name then description. build-lotr-tlk imports this; it does
    not get its own copy of the text.
    """
    out = []
    for feat in FEATS:
        out.append(feat.name)
        out.append(feat.description)
    return out


def nss_include():
    """Render unpacked/legfeat_ids_inc.nss - the script-side view of FEATS.

    Scripts read feat ids, names and descriptions from here rather than typing
    row numbers or re-writing the display text, so the 2DA, the TLK and every
    script move together. The names are inlined rather than looked up by strref
    because NUI labels need a string, not a strref.
    """
    lines = [
        "// legfeat_ids_inc.nss - GENERATED by bin/gen-legendary-feats.py. Do not edit.",
        "//",
        "// The script-side view of the legendary feat table. Feat ids are row indices",
        "// in hak_2da/feat.2da; the names and descriptions are the same strings that",
        "// bin/build-lotr-tlk writes into tlk/lotr.tlk, so what a script prints and",
        "// what the character sheet shows cannot drift apart.",
        "//",
        "// Re-run: python3 bin/gen-legendary-feats.py --apply",
        "",
        f"const int LEGFEAT_COUNT = {len(FEATS)};",
        f"const int LEGFEAT_FIRST = {FIRST_ROW};",
        "",
        "// How a feat's benefit is applied. RAW writes the character's BASE",
        "// ability score and is saved in the .bic, so it is applied exactly ONCE",
        "// and must never be re-applied at login. EFFECT is a permanent",
        "// supernatural effect and IS rebuilt on every login.",
        "// HOOK grants nothing at all - the feat is an inert token that a combat",
        "// hook elsewhere reads with GetHasFeat, so LegFeat_ApplyAll must skip it.",
        "const int LEGFEAT_KIND_EFFECT = 0;",
        "const int LEGFEAT_KIND_RAW    = 1;",
        "const int LEGFEAT_KIND_HOOK   = 2;",
        "",
    ]
    for offset, feat in enumerate(FEATS):
        lines.append(f"const int FEAT_{feat.label} = {FIRST_ROW + offset};")
    lines += [
        "",
        "// --- prerequisite helpers ------------------------------------------------",
        "// A `prereq` expression in the generator's table is rendered verbatim into",
        "// LegFeat_MeetsPrereq below, and THIS FILE HAS NO INCLUDES - so an",
        "// expression may only use NWScript builtins and the helpers here.",
        "//",
        "// Devastating Critical is not one feat: it is one feat PER WEAPON, ids 495",
        "// to 532 contiguous, plus 955 (dwarven waraxe) and 996 (whip) bolted on",
        "// later by the expansions. Anything gated on 'has Devastating Critical'",
        "// has to test the lot.",
        "int LegFeat_HasAnyDevCrit(object oPC)",
        "{",
        "    int nFeat;",
        "    for (nFeat = FEAT_EPIC_DEVASTATING_CRITICAL_CLUB;",
        "         nFeat <= FEAT_EPIC_DEVASTATING_CRITICAL_CREATURE; nFeat++)",
        "        if (GetHasFeat(nFeat, oPC)) return TRUE;",
        "",
        "    return GetHasFeat(FEAT_EPIC_DEVASTATING_CRITICAL_DWAXE, oPC)",
        "        || GetHasFeat(FEAT_EPIC_DEVASTATING_CRITICAL_WHIP, oPC);",
        "}",
        "",
        "// Feat id at picker index n (0 .. LEGFEAT_COUNT-1), or -1 if out of range.",
        "int LegFeat_IdAt(int n);",
        "// Display name / description for picker index n. Empty string if out of range.",
        "string LegFeat_NameAt(int n);",
        "string LegFeat_DescAt(int n);",
        "",
        "// Ability-score feats: the ABILITY_* constant a pick boosts (-1 if the",
        "// feat is not an ability feat) and the size of the bonus.",
        "int LegFeat_AbilityAt(int n);",
        "int LegFeat_BonusAt(int n);",
        "// LEGFEAT_KIND_* - how this feat's benefit is applied.",
        "int LegFeat_KindAt(int n);",
        "// Short summary for the picker's effect column (e.g. \"+6 Strength\").",
        "string LegFeat_EffectAt(int n);",
        "",
        "// Prerequisites. feat.2da gates nothing - these are the whole gate, and",
        "// they are enforced twice: the picker greys a row that fails, and",
        "// LegFeat_Take refuses it, so a stale window cannot buy past the check.",
        "// Ability prerequisites read BASE scores, so a +12 belt worn for the",
        "// duration of one button press does not qualify anyone.",
        "int    LegFeat_MeetsPrereq(object oPC, int n);",
        "// Player-facing prerequisite text, or \"\" when the feat has none.",
        "string LegFeat_PrereqAt(int n);",
        "// The same requirement MEASURED against this character: every clause,",
        "// each marked [ok] or [X], and each numeric one carrying the player's own",
        "// value - \"BAB 35+ (you have 34) [X], Epic Prowess [ok]\". A player who",
        "// cannot see WHICH clause failed reports the one they can see; that is",
        "// roadmap item legendary-feat-prereq-defect-1, where a character with a",
        "// qualifying BAB but no Epic Prowess read a greyed row as \"35 is not",
        "// accepted\". Returns \"\" when the feat has no prerequisite.",
        "string LegFeat_PrereqStatusAt(object oPC, int n);",
        "// Just the FIRST unmet clause, with its measured value - short enough for",
        "// the picker's effect column, which clips silently rather than wrapping.",
        "// \"\" when the character qualifies (or the feat has no prerequisite).",
        "string LegFeat_FirstUnmetAt(object oPC, int n);",
        "",
        "int LegFeat_IdAt(int n)",
        "{",
        "    if (n < 0 || n >= LEGFEAT_COUNT) return -1;",
        "    return LEGFEAT_FIRST + n;",
        "}",
        "",
        "string LegFeat_NameAt(int n)",
        "{",
        "    switch (n)",
        "    {",
    ]
    for offset, feat in enumerate(FEATS):
        lines.append(f'        case {offset}: return "{feat.name}";')
    lines += [
        "    }",
        '    return "";',
        "}",
        "",
        "string LegFeat_DescAt(int n)",
        "{",
        "    switch (n)",
        "    {",
    ]
    for offset, feat in enumerate(FEATS):
        text = feat.description.replace('"', "'")
        lines.append(f'        case {offset}: return "{text}";')
    lines += [
        "    }",
        '    return "";',
        "}",
        "",
        "int LegFeat_AbilityAt(int n)",
        "{",
        "    switch (n)",
        "    {",
    ]
    for offset, feat in enumerate(FEATS):
        lines.append(f"        case {offset}: return {feat.ability};")
    lines += [
        "    }",
        "    return -1;",
        "}",
        "",
        "int LegFeat_BonusAt(int n)",
        "{",
        "    switch (n)",
        "    {",
    ]
    for offset, feat in enumerate(FEATS):
        lines.append(f"        case {offset}: return {feat.bonus};")
    lines += [
        "    }",
        "    return 0;",
        "}",
        "",
        "int LegFeat_KindAt(int n)",
        "{",
        "    switch (n)",
        "    {",
    ]
    for offset, feat in enumerate(FEATS):
        kind = {
            "raw_ability": "LEGFEAT_KIND_RAW",
            "hook": "LEGFEAT_KIND_HOOK",
        }.get(feat.kind, "LEGFEAT_KIND_EFFECT")
        lines.append(f"        case {offset}: return {kind};")
    lines += [
        "    }",
        "    return LEGFEAT_KIND_EFFECT;",
        "}",
        "",
        "string LegFeat_EffectAt(int n)",
        "{",
        "    switch (n)",
        "    {",
    ]
    for offset, feat in enumerate(FEATS):
        lines.append(f'        case {offset}: return "{feat.effect}";')
    lines += [
        "    }",
        '    return "";',
        "}",
        "",
        "// --- clause renderers ----------------------------------------------------",
        "// The three functions below turn ONE clause into text. They exist so that",
        "// what the picker shows and what the picker tests come out of the same",
        "// declaration in the generator - the two used to be independent hand-typed",
        "// strings, which is how a player with a qualifying BAB and no Epic Prowess",
        "// came to report that \"35 is not accepted\" (legendary-feat-prereq-defect-1).",
        "",
        "// The ask, unmeasured: \"BAB 35+\", \"Discipline 30+ ranks\".",
        "string LegFeat_ReqAsk(string sLabel, int nMin, string sUnit)",
        "{",
        '    string s = sLabel + " " + IntToString(nMin) + "+";',
        '    if (sUnit != "") s += " " + sUnit;',
        "    return s;",
        "}",
        "",
        "// The ask with this character's own value: \"BAB 35+ (you have 34)\".",
        "string LegFeat_ReqHave(string sLabel, int nMin, string sUnit, int nHave)",
        "{",
        "    return LegFeat_ReqAsk(sLabel, nMin, sUnit)",
        '         + " (you have " + IntToString(nHave) + ")";',
        "}",
        "",
        "// Pass/fail marker. ASCII on purpose - a non-ASCII byte in a .nss is a",
        "// recorded trap in this repo, and this string reaches the NUI and the chat",
        "// log both.",
        "string LegFeat_ReqMark(string sBody, int bMet)",
        "{",
        '    return sBody + (bMet ? " [ok]" : " [X]");',
        "}",
        "",
        "// A numeric clause, fully rendered. nHave is passed in so the generator can",
        "// evaluate the getter exactly once at the call site.",
        "string LegFeat_ReqNum(string sLabel, int nMin, string sUnit, int nHave)",
        "{",
        "    return LegFeat_ReqMark(LegFeat_ReqHave(sLabel, nMin, sUnit, nHave),",
        "                           nHave >= nMin);",
        "}",
        "",
        "// Each case ANDs the feat's clauses from the generator's table. A numeric",
        "// clause is always emitted as `(expr) >= minimum` - the generator cannot",
        "// express `>`, which is what makes \"treated as >=, not >\" a property of the",
        "// build rather than a habit. A feat with no prerequisite emits no case and",
        "// falls through to TRUE.",
        "int LegFeat_MeetsPrereq(object oPC, int n)",
        "{",
        "    switch (n)",
        "    {",
    ]
    for offset, feat in enumerate(FEATS):
        if feat.reqs:
            test = " && ".join(r.nss_test() for r in feat.reqs)
            lines.append(f"        case {offset}: return ({test});")
    lines += [
        "    }",
        "    return TRUE;",
        "}",
        "",
        "string LegFeat_PrereqAt(int n)",
        "{",
        "    switch (n)",
        "    {",
    ]
    for offset, feat in enumerate(FEATS):
        if feat.reqs:
            text = ", ".join(r.text() for r in feat.reqs).replace('"', "'")
            lines.append(f'        case {offset}: return "{text}";')
    lines += [
        "    }",
        '    return "";',
        "}",
        "",
        "string LegFeat_PrereqStatusAt(object oPC, int n)",
        "{",
        "    switch (n)",
        "    {",
    ]
    for offset, feat in enumerate(FEATS):
        if not feat.reqs:
            continue
        parts = []
        for r in feat.reqs:
            label = r.label.replace('"', "'")
            unit = r.unit.replace('"', "'")
            if r.is_numeric:
                parts.append(f'LegFeat_ReqNum("{label}", {r.minimum}, '
                             f'"{unit}", {r.expr})')
            else:
                parts.append(f'LegFeat_ReqMark("{label}", {r.expr})')
        joined = '\n                 + ", " + '.join(parts)
        lines.append(f"        case {offset}: return {joined};")
    lines += [
        "    }",
        '    return "";',
        "}",
        "",
        "string LegFeat_FirstUnmetAt(object oPC, int n)",
        "{",
        "    switch (n)",
        "    {",
    ]
    for offset, feat in enumerate(FEATS):
        if not feat.reqs:
            continue
        lines.append(f"        case {offset}:")
        for r in feat.reqs:
            label = r.label.replace('"', "'")
            unit = r.unit.replace('"', "'")
            lines.append(f"            if (!({r.nss_test()}))")
            if r.is_numeric:
                lines.append(f'                return LegFeat_ReqHave("{label}", '
                             f'{r.minimum}, "{unit}", {r.expr});')
            else:
                lines.append(f'                return "{label}";')
        lines.append("            break;")
    lines += [
        "    }",
        '    return "";',
        "}",
        "",
    ]
    return "\n".join(lines)


def strrefs():
    """Return {label: (name_strref, description_strref)}.

    Derived from where bin/build-lotr-tlk actually places our strings, so the
    2DA cannot drift from the TLK by a transcription error. The import is
    one-directional — build-lotr-tlk pulls tlk_strings() from here inside a
    function, so importing it back at module scope is not a cycle.
    """
    spec = importlib.util.spec_from_file_location(
        "build_lotr_tlk", TLK_GENERATOR,
        loader=importlib.machinery.SourceFileLoader(
            "build_lotr_tlk", str(TLK_GENERATOR)),
    )
    tlk = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(tlk)

    strings = tlk.owned_strings()
    base = tlk.BLOCK_START + tlk.CUSTOM_TLK_OFFSET
    out = {}
    for feat in FEATS:
        try:
            name_pos = strings.index(feat.name)
            desc_pos = strings.index(feat.description)
        except ValueError:  # pragma: no cover - guarded by the gate too
            raise SystemExit(
                f"error: {feat.label}'s strings are not in bin/build-lotr-tlk's "
                "block - it must append tlk_strings() from this module")
        out[feat.label] = (base + name_pos, base + desc_pos)
    return out


# ---------------------------------------------------------------------------
# Stock rows we override
#
# These are Bioware's own feats, not ours. We only touch them when the module
# has changed what the feat DOES and the shipped description has become a lie —
# a player reading "must succeed at a Fortitude save or die" builds around a
# rule that has not applied since the devcrit-roll rework. The row keeps its
# name, id, prerequisites and everything else; only DESCRIPTION moves, to a
# string in our own TLK block.
#
# Devastating Critical is one feat per weapon: 495-532 contiguous, plus 955
# (dwarven waraxe) and 996 (whip) added by the expansions. 39 of the 40 share
# the stock description strref and the creature-weapon row has its own; both
# are replaced, so the text is consistent whichever weapon the player took.
# ---------------------------------------------------------------------------
DEVCRIT_ROWS = list(range(495, 533)) + [955, 996]


def stock_overrides():
    """{row index: {column: new value}} for stock rows we repoint.

    The strref comes from bin/build-lotr-tlk, which owns the text, so the 2DA
    cannot drift from the TLK by a transcription error — the same one-way
    import strrefs() already uses for the legendary feats.
    """
    spec = importlib.util.spec_from_file_location(
        "build_lotr_tlk", TLK_GENERATOR,
        loader=importlib.machinery.SourceFileLoader(
            "build_lotr_tlk", str(TLK_GENERATOR)),
    )
    tlk = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(tlk)
    devcrit = tlk.stock_override_strref(tlk.STOCK_OVERRIDE_STRINGS[0])
    return {row: {"DESCRIPTION": str(devcrit)} for row in DEVCRIT_ROWS}


# ---------------------------------------------------------------------------
# 2DA reading and writing
# ---------------------------------------------------------------------------

def read_2da(path):
    """Return (preamble_lines, header_columns, {row_index: raw_line}, newline).

    The newline comes back with the rest: 2DAs from the game data use CRLF, and
    rewriting rows 0-1115 with bare LF would make every one of them differ —
    "byte-identical base rows" has to mean the bytes, not just the tokens.
    """
    raw = path.read_bytes()
    newline = "\r\n" if b"\r\n" in raw else "\n"
    lines = raw.decode("latin-1").splitlines()
    if len(lines) < 3:
        raise SystemExit(f"error: {path} is not a 2DA")
    preamble = lines[:3]
    header = lines[2].split()
    rows = {}
    for line in lines[3:]:
        cells = line.split()
        if not cells or not cells[0].isdigit():
            continue
        rows[int(cells[0])] = line
    return preamble, header, rows, newline


def check_base(path, preamble, header, rows):
    """The base must be the stock table: 1116 rows, 43 columns."""
    problems = []
    if len(header) != BASE_COLUMNS:
        problems.append(
            f"{len(header)} columns, expected {BASE_COLUMNS} - this is not the "
            "stock feat.2da (the CEP cep2_add_feats copy has 44)")
    base_rows = [i for i in rows if i < FIRST_ROW]
    if len(base_rows) != BASE_ROWS or max(base_rows, default=-1) != BASE_ROWS - 1:
        problems.append(
            f"{len(base_rows)} rows below {FIRST_ROW}, expected {BASE_ROWS} "
            "(0-1115, last PLAYER_TOOL_10)")
    if problems:
        raise SystemExit(
            f"error: {path} is not a usable base table:\n"
            + "".join(f"       - {p}\n" for p in problems)
            + "       Seed a fresh stock base with --from-stock; see this "
              "script's docstring for the nwn_resman_cat command.")


def build_cells(index, feat, refs, header):
    """Render one owned row. Everything except name/description/icon is inert."""
    name_ref, desc_ref = refs[feat.label]
    values = {
        "LABEL": feat.label,
        "FEAT": str(name_ref),
        "DESCRIPTION": str(desc_ref),
        "ICON": feat.icon,
        # GAINMULTIPLE 0 / EFFECTSSTACK 0: taken once, no stacking rule for the
        # engine to apply — the script owns the effect.
        "GAINMULTIPLE": "0",
        "EFFECTSSTACK": "0",
        # THE load-bearing column. 0 = only classes whose cls_feat_*.2da lists
        # this feat may select it, and no cls_feat table lists ours, so the
        # engine's level-up page can never offer it. The picker grants it with
        # NWNX_Creature_AddFeat, which does not consult this.
        "ALLCLASSESCANUSE": "0",
        "Constant": f"FEAT_{feat.label}",
        # Toolset category 6 ("special"), so a builder can still hand one to an
        # NPC blueprint. Harmless: the toolset is not the level-up page.
        "TOOLSCATEGORIES": "6",
        # PreReqEpic 0 / ReqAction 0: no epic-page gating, not an activated
        # ability. Both are inert while ALLCLASSESCANUSE is 0; they are set
        # explicitly so a future reader does not read **** as "undecided".
        "PreReqEpic": "0",
        "ReqAction": "0",
    }
    return [str(index)] + [values.get(col, BLANK) for col in header]


def render(cells, widths):
    return "".join(c.ljust(w) for c, w in zip(cells, widths)).rstrip()


def column_widths(header, rows, owned_cells):
    """Match the base table's column alignment so a diff stays readable.

    Measured across every base row, not just the first — the LABEL column is
    sized for the longest feat name in the table, and padding our rows to the
    first row's width instead would run cells together with no separator.
    """
    widths = [6] + [len(c) + 2 for c in header]
    # Base rows only. Measuring our own rows too would make the widths depend on
    # the previous run's output — our long custom strrefs would widen the FEAT
    # column on run 2 and the script would never settle.
    for index, line in rows.items():
        if index >= FIRST_ROW:
            continue
        for i, cell in enumerate(line.split()):
            if i < len(widths):
                widths[i] = max(widths[i], len(cell) + 2)
    # Our own cells too, so a long custom strref still gets a separator after
    # it. Safe for idempotence: those cells come from FEATS, not from the file
    # we are about to overwrite.
    for cells in owned_cells:
        for i, cell in enumerate(cells):
            if i < len(widths):
                widths[i] = max(widths[i], len(cell) + 2)
    return widths


def main():
    ap = argparse.ArgumentParser(
        description="Own the legendary feat rows in hak_2da/feat.2da.")
    ap.add_argument("--apply", action="store_true",
                    help="write the table (default is a dry run)")
    ap.add_argument("--from-stock", metavar="PATH", type=Path,
                    help="reseed rows 0-1115 from a freshly extracted stock "
                         "feat.2da, keeping our rows")
    args = ap.parse_args()

    source = args.from_stock or FEAT_2DA
    if not source.exists():
        print(f"error: {source} is missing", file=sys.stderr)
        return 1

    # A prerequisite the player is never told about is indistinguishable from a
    # broken picker ("why is that row greyed out?"), and prose with no test
    # behind it is a prerequisite that is not enforced. A Req carries both
    # halves, so the two can no longer be written separately — what is left to
    # check is that each clause is well formed.
    for feat in FEATS:
        for req in feat.reqs:
            if not req.label or not req.expr:
                print(f"error: {feat.label} has a clause missing its label or "
                      "its test", file=sys.stderr)
                return 1
            if req.is_numeric and req.minimum <= 0:
                print(f"error: {feat.label} clause {req.label!r} has a "
                      f"non-positive minimum ({req.minimum}) — a numeric clause "
                      "renders as \"N+\" and is meaningless at or below zero",
                      file=sys.stderr)
                return 1
            if not req.is_numeric and req.unit:
                print(f"error: {feat.label} clause {req.label!r} sets a unit but "
                      "has no minimum — units only render on numeric clauses",
                      file=sys.stderr)
                return 1

    preamble, header, rows, newline = read_2da(source)
    check_base(source, preamble, header, rows)
    refs = strrefs()
    kept = {i: line for i, line in rows.items() if i < FIRST_ROW}

    # Repoint the stock rows we have changed the behaviour of. Done on `kept`
    # so a --from-stock reseed picks the override up again automatically:
    # re-extracting the table is exactly when this would otherwise be lost, and
    # the only symptom would be a feat quietly describing the old rule.
    overrides = stock_overrides()
    patched = 0
    for row, changes in sorted(overrides.items()):
        line = kept.get(row)
        if line is None:
            print(f"error: stock row {row} is missing from {source}",
                  file=sys.stderr)
            return 1
        cells = line.split()
        for column, value in changes.items():
            position = 1 + header.index(column)
            if cells[position] != value:
                cells[position] = value
                patched += 1
        kept[row] = cells
    owned_cells = {
        FIRST_ROW + offset: build_cells(FIRST_ROW + offset, feat, refs, header)
        for offset, feat in enumerate(FEATS)
    }
    widths = column_widths(header, rows, owned_cells.values())
    owned = {i: render(cells, widths) for i, cells in owned_cells.items()}

    print(f"[feat] base:  {source}  ({len(kept)} rows, {len(header)} columns)")
    print(f"[feat] owned: {len(owned)} row(s) from {FIRST_ROW}")
    print(f"[feat] stock: {len(overrides)} row(s) repointed at our TLK "
          f"({patched} cell(s) changed this run)")
    for index, feat in zip(sorted(owned), FEATS):
        name_ref, desc_ref = refs[feat.label]
        print(f"        {index}  FEAT_{feat.label}  "
              f"name={name_ref} desc={desc_ref}  {feat.effect}")

    base_lines = [
        render(kept[i], widths) if isinstance(kept[i], list) else kept[i]
        for i in sorted(kept)
    ]
    out_lines = preamble + base_lines + [owned[i] for i in sorted(owned)]
    text = newline.join(out_lines) + newline

    if not args.apply:
        print()
        print(f"Dry run. Nothing written. Re-run with --apply to write {FEAT_2DA}.")
        return 0

    payload = text.encode("latin-1")
    unchanged = FEAT_2DA.exists() and FEAT_2DA.read_bytes() == payload
    FEAT_2DA.write_bytes(payload)
    print()
    print(f"[feat] {'unchanged' if unchanged else 'wrote'} -> {FEAT_2DA}")

    inc = nss_include()
    inc_same = IDS_INC.exists() and IDS_INC.read_text(encoding="utf-8") == inc
    IDS_INC.write_text(inc, encoding="utf-8")
    print(f"[feat] {'unchanged' if inc_same else 'wrote'} -> {IDS_INC}")
    unchanged = unchanged and inc_same
    if not unchanged:
        print()
        print("Next: bin/build-lotr-tlk --apply --install   # the rows point at "
              "strrefs only lotr.tlk has")
        print("      bin/build-lotr-rules-hak --install")
        print("      bin/refresh-nwsync && nwn-manager repack && bin/server-restart")
    return 0


if __name__ == "__main__":
    sys.exit(main())
