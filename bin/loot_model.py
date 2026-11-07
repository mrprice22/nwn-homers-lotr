"""loot_model.py - the one Python implementation of the Loot Overhaul data model.

Season 3 rolled loot (roadmap epic ``loot-overhaul``, phase 2 ``lo-loot-core``;
design: docs.manual/Draft/Loot-Overhaul.html).  The game reads the same
``loot/*.json`` through the generated ``unpacked/loot_data_inc.nss``; this
module is what turns that JSON into the include, checks it, and simulates it:

    bin/gen-loot-tables.py      JSON -> unpacked/loot_data_inc.nss
    tests/check_loot_tables.py  the repack gate
    bin/loot-sim.py             Monte Carlo balance tables

All three import this file, so they can never disagree about what the data
means.  ``roll()`` mirrors ``Loot_Roll()`` in ``unpacked/loot_inc.nss`` step for
step -- change one, change the other.

Values: ``CostModel.item_value`` is NWN's item-cost formula over the 2DA cost
columns snapshotted in ``loot/_costs.json``.  It reproduces the toolset's
stored ``Cost`` for ~88% of the module's blueprints (the rest are hand-priced
or were saved under older 2DAs).  It is an estimate for balance and for the
gate; at runtime the engine's own ``GetGoldPieceValue`` on a forge blank is
what enforces the budget, exactly as the forge prices items.

Pure stdlib.  Nothing here may import from nwn_manager.
"""

from __future__ import annotations

import json
import random
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
LOOT_DIR = ROOT / "loot"
UNPACKED = ROOT / "unpacked"
INCLUDE = UNPACKED / "loot_data_inc.nss"
# Phase 5: socket gems + existing-item socket rules, a separate include so the
# thirty container wrappers that pull in loot_inc never carry it.
SOCKET_INCLUDE = UNPACKED / "socket_data_inc.nss"
HAK_2DA = ROOT / "hak_2da"

# The forge's global property ceiling (forge_inc.nss FORGE_LEGAL_MAX_PROPS).
# A rolled item never carries more random properties than a forge may.
FORGE_LEGAL_MAX_PROPS = 6
# Highest per-forge value cap (kallristcryptlow.are.json FORGE_MAX_VALUE) and
# the global ceiling (ForgeLegalMaxValue()).  Rolls may exceed them -- like the
# module's existing top gear, such an item simply cannot be worked further --
# loot-sim reports how often.
FORGE_CAPS = {"tagget": 250000, "rivendell": 500000, "kallrist": 750000,
              "global": 900000}

RARITY_COLORS = ("COLOR_WHITE", "COLOR_GREEN", "COLOR_BLUE", "COLOR_PURPLE",
                 "COLOR_ORANGE", "COLOR_LIGHT_BLUE", "COLOR_LIGHT_ORANGE",
                 "COLOR_LIGHT_PURPLE", "COLOR_YELLOW", "COLOR_RED", "COLOR_GRAY")

CATEGORIES = ("melee", "ranged", "armor", "shield", "jewelry", "wearable",
              "caster")

MAX_LEVEL = 60

# Item property types loot may roll, and the NWScript constructor for each.
# {sub} = the affix's subtype row, {cost} = the chosen cost-table row.  The
# generator emits Loot_MakeIP() from this table, so the runtime switch and the
# validator can never drift.  (x2_inc_itemprop's IPGetItemPropertyByID is NOT
# used: it builds DAMAGE_VULNERABILITY as a resistance and
# DECREASED_SAVING_THROWS_SPECIFIC as a bonus.)
SUPPORTED_IP = {
    0:  ("Ability Bonus",             "ItemPropertyAbilityBonus({sub}, {cost})"),
    1:  ("AC Bonus",                  "ItemPropertyACBonus({cost})"),
    6:  ("Enhancement Bonus",         "ItemPropertyEnhancementBonus({cost})"),
    13: ("Bonus Spell Slot",          "ItemPropertyBonusLevelSpell({sub}, {cost})"),
    16: ("Damage Bonus",              "ItemPropertyDamageBonus({sub}, {cost})"),
    20: ("Damage Immunity",           "ItemPropertyDamageImmunity({sub}, {cost})"),
    22: ("Damage Reduction",          "ItemPropertyDamageReduction({sub}, {cost})"),
    23: ("Damage Resistance",         "ItemPropertyDamageResistance({sub}, {cost})"),
    24: ("Damage Vulnerability",      "ItemPropertyDamageVulnerability({sub}, {cost})"),
    26: ("Darkvision",                "ItemPropertyDarkvision()"),
    27: ("Decreased Ability",         "ItemPropertyDecreaseAbility({sub}, {cost})"),
    28: ("Decreased AC",              "ItemPropertyDecreaseAC({sub}, {cost})"),
    29: ("Decreased Skill",           "ItemPropertyDecreaseSkill({sub}, {cost})"),
    37: ("Immunity: Misc",            "ItemPropertyImmunityMisc({sub})"),
    38: ("Improved Evasion",          "ItemPropertyImprovedEvasion()"),
    39: ("Spell Resistance",          "ItemPropertyBonusSpellResistance({cost})"),
    40: ("Saving Throw Bonus",        "ItemPropertyBonusSavingThrowVsX({sub}, {cost})"),
    41: ("Saving Throw Bonus: Specific", "ItemPropertyBonusSavingThrow({sub}, {cost})"),
    43: ("Keen",                      "ItemPropertyKeen()"),
    45: ("Mighty",                    "ItemPropertyMaxRangeStrengthMod({cost})"),
    49: ("Decreased Saving Throws",   "ItemPropertyReducedSavingThrowVsX({sub}, {cost})"),
    50: ("Decreased Saving Throws: Specific", "ItemPropertyReducedSavingThrow({sub}, {cost})"),
    51: ("Regeneration",              "ItemPropertyRegeneration({cost})"),
    52: ("Skill Bonus",               "ItemPropertySkillBonus({sub}, {cost})"),
    56: ("Attack Bonus",              "ItemPropertyAttackBonus({cost})"),
    60: ("Decreased Attack",          "ItemPropertyAttackPenalty({cost})"),
    67: ("Vampiric Regeneration",     "ItemPropertyVampiricRegeneration({cost})"),
    71: ("True Seeing",               "ItemPropertyTrueSeeing()"),
    74: ("Massive Criticals",         "ItemPropertyMassiveCritical({cost})"),
    75: ("Freedom of Movement",       "ItemPropertyFreeAction()"),
    84: ("Arcane Spell Failure",      "ItemPropertyArcaneSpellFailure({cost})"),
}

# Property types whose NWScript constructor refuses this module's hak-extended
# cost rows, so Loot_MakeIP copies them from the generated donor item
# (DONOR_RESREF, created once in FORGE_VAULT) instead of calling the
# constructor.  Found 2026-11-07 (roadmap lo-imm-affix-dropped):
# ItemPropertyDamageImmunity() returns an invalid property for any
# iprp_immuncost row above the stock 7, while the module's 1%-step rows are
# 51-150 - every imm_* roll was silently dropped.  A property loaded from a
# blueprint's GFF is not range-checked, so the donor carries every row the
# ladders use.  Resistance, SR, damage and soak constructors accept their
# extended rows (no failures in the dev log), so they are not here.
DONOR_TYPES = {20: "ItemPropertyDamageImmunity rejects cost rows above 7"}
DONOR_RESREF = "loot_ipdonor"
DONOR_BASE = 24          # miscsmall, like the forge blanks
DONOR_PALETTE = 54       # the forge blanks' palette category
DONOR_COST_TABLE = {20: 5}   # iprp_costtable row of iprp_immuncost

# Never rolled, whatever affixes.json says (the gate rejects them):
#   Haste / extra attacks and Divine damage - season3-meta-shakeup: a drop that
#   is "a bigger number on those axes changes nothing";
#   Critical-hit immunity - the devcrit rework (CLAUDE-devcrit-immunity-audit.md).
BANNED = {
    "type": {35: "Haste (attacks per round)"},
    "damage_type_sub": {8: "Divine damage"},
    "immunity_misc_sub": {8: "Critical-hit immunity"},
}

# Properties the engine prices as negative (NegMultiplier).
NEGATIVE_TYPES = {10, 21, 24, 27, 28, 29, 49, 50, 60, 81}

# ArmorPart_* field per ITEM_APPR_ARMOR_MODEL_* index 0..18.
ARMOR_PARTS = ("RFoot", "LFoot", "RShin", "LShin", "LThigh", "RThigh", "Pelvis",
               "Torso", "Belt", "Neck", "RFArm", "LFArm", "RBicep", "LBicep",
               "RShoul", "LShoul", "RHand", "LHand", "Robe")
TORSO = ARMOR_PARTS.index("Torso")


# --------------------------------------------------------------------------
# Loading
# --------------------------------------------------------------------------

def _load(name):
    p = LOOT_DIR / name
    with p.open(encoding="utf-8") as f:
        return json.load(f)


def load_data():
    """Every loot/*.json file, keyed by stem.  ``costs`` is the 2DA snapshot,
    ``items`` the stock-item snapshot (gen-loot-consumables.py --refresh-items)."""
    d = {}
    for stem in ("rarity", "levels", "bases", "affixes", "named", "sources"):
        d[stem] = _load(stem + ".json")
    d["costs"] = _load("_costs.json")
    # Phase 3 files; empty until their tools first write them.
    for stem, empty in (("consumables", {"items": []}), ("treasure", {"gems": []}),
                        ("area_levels", {"areas": {}}), ("_items", {"items": {}}),
                        # Phase 5 (sockets and gems)
                        ("gems", {"families": [], "tiers": [], "level_bands": []}),
                        ("sockets", {}),
                        # Phase 7 (the Shard of Fate)
                        ("tokens", {})):
        d[stem.lstrip("_")] = _load(stem + ".json") if (LOOT_DIR / (stem + ".json")).exists() else empty
    return d


def gff(obj, key, default=None):
    v = obj.get(key)
    if isinstance(v, dict) and "value" in v:
        return v["value"]
    return default


def load_uti(resref):
    p = UNPACKED / (resref + ".uti.json")
    if not p.exists():
        return None
    with p.open(encoding="utf-8") as f:
        return json.load(f)


# --------------------------------------------------------------------------
# Interpolation (integer, identical to the NWScript side)
# --------------------------------------------------------------------------

def interp_points(points, x):
    """Piecewise-linear over sorted [[x, y], ...] with integer maths, clamped.

    Mirrors the generated LootD_* interpolators: y0 + (y1-y0)*(x-x0)/(x1-x0)
    using C-style truncating division (NWScript int division)."""
    if x <= points[0][0]:
        return points[0][1]
    for (x0, y0), (x1, y1) in zip(points, points[1:]):
        if x <= x1:
            return y0 + _cdiv((y1 - y0) * (x - x0), (x1 - x0))
    return points[-1][1]


def _cdiv(a, b):
    q = abs(a) // abs(b)
    return q if (a >= 0) == (b > 0) else -q


def curve(obj):
    """{"1": v, "60": w} -> sorted [[1, v], [60, w]]."""
    return sorted([int(k), int(v)] for k, v in obj.items())


def affix_window(aff, level):
    """(lo, hi) ladder indices for this affix at loot level ``level``."""
    w = aff["window"]
    lo = interp_points(sorted([int(k), int(v[0])] for k, v in w.items()), level)
    hi = interp_points(sorted([int(k), int(v[1])] for k, v in w.items()), level)
    return lo, max(lo, hi)


def rarity_budget(tier, level, downside=False):
    b = interp_points(curve(tier["budget"]), level)
    if downside:
        b = b * (100 + int(tier.get("downside_budget_pct", 0))) // 100
    return b


def level_for_cr(levels, cr):
    """CR -> loot level 1..60 (float CR, truncating like NWScript FloatToInt)."""
    pts = levels["cr_points"]
    if cr <= pts[0][0]:
        return int(pts[0][1])
    for (x0, y0), (x1, y1) in zip(pts, pts[1:]):
        if cr <= x1:
            return int(y0 + (y1 - y0) * (cr - x0) / (x1 - x0))
    return int(pts[-1][1])


# --------------------------------------------------------------------------
# Area loot levels (Phase 3) -- bin/gen-area-loot-levels.py writes them to
# loot/area_levels.json; the gate recomputes them from here, so the two can
# never disagree.
# --------------------------------------------------------------------------

# Placeable event fields a treasure script can sit on.
TREASURE_EVENTS = ("OnOpen", "OnDeath", "OnUsed")


def hostile_factions():
    """Faction ids whose reputation toward the PC faction (0) is <= 10.

    repute.fac RepList: FactionRep is how FactionID2 regards FactionID1, so the
    rows with FactionID1 == 0 say how each faction regards players."""
    with (UNPACKED / "repute.fac.json").open(encoding="utf-8") as f:
        d = json.load(f)
    out = set()
    for r in gff(d, "RepList", []):
        if gff(r, "FactionID1") == 0 and gff(r, "FactionID2") != 0 \
                and int(gff(r, "FactionRep", 100)) <= 10:
            out.add(int(gff(r, "FactionID2")))
    return out


def _median(xs):
    xs = sorted(xs)
    n = len(xs)
    if not n:
        return None
    m = n // 2
    return xs[m] if n % 2 else (xs[m - 1] + xs[m]) / 2.0


def _percentile(xs, p):
    """The p-th percentile (0..100) of xs, linearly interpolated between the two
    nearest ranks (numpy's default); None for an empty list.  p=50 is the median."""
    xs = sorted(xs)
    if not xs:
        return None
    k = (len(xs) - 1) * p / 100.0
    i = int(k)
    j = min(i + 1, len(xs) - 1)
    return xs[i] + (xs[j] - xs[i]) * (k - i)


DEFAULT_AREA_PERCENTILE = 50


def area_percentile(data):
    """levels.json "area_percentile": which CR percentile of an area's hostiles
    sets its loot level.  50 = the median.  75 was tried and reverted on
    2026-11-06: any creature that is a quarter or more of an area's hostiles
    then sets the area's level itself, so buffing it can never make it elite."""
    return data["levels"].get("area_percentile", DEFAULT_AREA_PERCENTILE)


_GIT_CACHE = None


def load_gits():
    """[(area resref, parsed .git.json)] for every area, read once per process."""
    global _GIT_CACHE
    if _GIT_CACHE is None:
        _GIT_CACHE = []
        for p in sorted(UNPACKED.glob("*.git.json")):
            with p.open(encoding="utf-8") as f:
                _GIT_CACHE.append((p.name[:-len(".git.json")], json.load(f)))
    return _GIT_CACHE


def creature_slots(also=frozenset()):
    """Every hostile creature slot in the module, as dicts {area, resref, cr, kind}.

    kind "placed" = a placed creature instance (its instance ChallengeRating and
    FactionID); kind "encounter" = an entry in a placed encounter's creature list
    (its CR and the encounter's Faction).  Hostile = hostile_factions(); a resref
    in ``also`` is included whatever its faction (registered bosses drop even
    when placed as Commoners who turn hostile in conversation).  This is the one
    definition both the area loot levels and the creature-drop report read."""
    hostile = hostile_factions()
    out = []
    for area, d in load_gits():
        for c in gff(d, "Creature List", []) or []:
            rr = gff(c, "TemplateResRef", "") or ""
            if gff(c, "FactionID", -1) in hostile or rr in also:
                out.append({"area": area, "resref": rr,
                            "cr": float(gff(c, "ChallengeRating", 0) or 0), "kind": "placed"})
        for e in gff(d, "Encounter List", []) or []:
            hos = gff(e, "Faction", 1) in hostile
            for c in gff(e, "CreatureList", []) or []:
                rr = gff(c, "ResRef", "") or ""
                if hos or rr in also:
                    out.append({"area": area, "resref": rr,
                                "cr": float(gff(c, "CR", 0) or 0), "kind": "encounter"})
    return out


def area_scan(scripts, percentile=DEFAULT_AREA_PERCENTILE):
    """{area resref: {"area_cr", "hostiles", "chests"}} for every area.

    area_cr: the ``percentile``-th percentile CR of creature_slots() in the area
    (placed hostile instances + placed hostile encounter lists).  ``chests`` counts placeables with any of ``scripts``
    (loot/sources.json "scripts") on a TREASURE_EVENTS field."""
    scripts = {s.lower() for s in scripts}
    crs = {}
    for sl in creature_slots():
        crs.setdefault(sl["area"], []).append(sl["cr"])
    out = {}
    for area, d in load_gits():
        chests = 0
        for pl in gff(d, "Placeable List", []) or []:
            if any(str(gff(pl, ev, "") or "").lower() in scripts for ev in TREASURE_EVENTS):
                chests += 1
        a_crs = crs.get(area, [])
        pc = _percentile(a_crs, percentile)
        out[area] = {"area_cr": None if pc is None else round(pc, 2),
                     "hostiles": len(a_crs), "chests": chests}
    return out


def area_levels_doc(data, scan=None):
    """The content of loot/area_levels.json: scan + overrides -> levels."""
    pct = area_percentile(data)
    scan = scan if scan is not None else area_scan(data["sources"].get("scripts", {}), pct)
    over = data["sources"].get("area_overrides", {})
    areas = {}
    for a, r in sorted(scan.items()):
        ent = dict(r)
        if a in over:
            ent["level"] = int(over[a]["level"])
            ent["source"] = "override"
        elif r["area_cr"] is not None:
            ent["level"] = level_for_cr(data["levels"], r["area_cr"])
            ent["source"] = "percentile"
        else:
            ent["level"] = None
            ent["source"] = "none"
        areas[a] = ent
    return {"_doc": "GENERATED by bin/gen-area-loot-levels.py --apply. Do not edit. Each "
                    "area's loot level: area_cr = the %d th percentile CR of its hostile "
                    "creatures (placed + encounter pools; levels.json area_percentile) "
                    "through levels.json, or loot/sources.json area_overrides. Chests roll "
                    "at this level (Loot Overhaul Phase 3); Phase 4 elites are measured "
                    "against it." % pct,
            "areas": areas}


def dump_area_levels(doc):
    """area_levels.json text, one area per line so diffs stay readable."""
    lines = ["{", '  "_doc": %s,' % json.dumps(doc["_doc"]), '  "areas": {']
    items = list(doc["areas"].items())
    for i, (a, e) in enumerate(items):
        lines.append("    %s: %s%s" % (json.dumps(a), json.dumps(e, sort_keys=True),
                                       "," if i < len(items) - 1 else ""))
    lines += ["  }", "}"]
    return "\n".join(lines) + "\n"


# --------------------------------------------------------------------------
# 2DA reading (used only by --refresh-costs) + the cost model
# --------------------------------------------------------------------------

def read_2da_text(text):
    """Parse a 2DA V2.0 text into (header, {row: {col: value}})."""
    import shlex
    hdr = None
    rows = {}
    for ln in text.splitlines()[1:]:
        if not ln.strip():
            continue
        try:
            parts = shlex.split(ln)
        except ValueError:
            parts = ln.split()
        if hdr is None:
            hdr = parts
            continue
        if not parts or not parts[0].isdigit():
            continue
        rows[int(parts[0])] = dict(zip(hdr, parts[1:]))
    return hdr or [], rows


def _num(x, default=None):
    try:
        return float(x)
    except (TypeError, ValueError):
        return default


class CostModel:
    """NWN item cost: [BaseCost + 1000*(Mult^2 - NegMult^2)] * ItemMultiplier.

    Mult = sum over positive properties of (itempropdef Cost, or the subtype
    table's Cost when that is ****) * (cost-table row's Cost)."""

    def __init__(self, costs):
        self.c = costs

    def prop_cost(self, ptype, sub, cost):
        d = self.c["itempropdef"].get(str(ptype))
        if not d:
            return 0.0
        base = d.get("cost")
        if base is None:
            st = d.get("subtype_table")
            base = (self.c["subtype_costs"].get(st, {}).get(str(sub), 0.0)
                    if st else 0.0)
        ct = d.get("cost_table")
        mult = 1.0
        if ct:
            mult = self.c["cost_tables"].get(ct, {}).get(str(cost), 0.0)
        return float(base) * float(mult)

    def base_cost(self, base_row):
        b = self.c["baseitems"][str(base_row)]
        if b.get("armor_ac") is not None:
            return float(self.c["armor_cost"].get(str(b["armor_ac"]), 0))
        return float(b.get("base_cost") or 0)

    def item_value(self, base_row, props):
        """props: iterable of (type, sub, cost)."""
        pos = neg = 0.0
        for t, s, c in props:
            v = self.prop_cost(t, s, c)
            if t in NEGATIVE_TYPES:
                neg += v
            else:
                pos += v
        b = self.c["baseitems"][str(base_row)]
        mult = float(b.get("mult") or 1)
        return int((self.base_cost(base_row) + 1000 * (pos * pos - neg * neg)) * mult)


# --------------------------------------------------------------------------
# The roll -- mirrors Loot_Roll() in unpacked/loot_inc.nss
# --------------------------------------------------------------------------

def weighted(rng, items, weight):
    """Pick from ``items`` by integer ``weight(item)``; NWScript does the same
    with Random(total) over a running sum."""
    total = sum(weight(i) for i in items)
    if total <= 0:
        return None
    r = rng.randrange(total)
    for i in items:
        r -= weight(i)
        if r < 0:
            return i
    return None


def pick_rarity(data, rng, floor):
    tiers = data["rarity"]["tiers"]
    idx = weighted(rng, list(range(len(tiers))), lambda i: tiers[i]["weight"])
    idx = max(idx, floor)
    t = tiers[idx]
    roll = rng.randrange(1000)
    if roll < t.get("upgrade_two", 0):
        idx += 2
    elif roll < t.get("upgrade_two", 0) + t.get("upgrade_one", 0):
        idx += 1
    return min(idx, len(tiers) - 1)


def eligible(aff, cat, level, role, used_groups):
    return (cat in aff["cats"] and aff["role"] == role
            and level >= aff.get("min_level", 1)
            and aff["weight"] > 0 and aff["group"] not in used_groups)


def roll_affixes(data, cat, level, tier, base_row, rng, model, block=frozenset(),
                 max_new=None, total_fn=None, total_cap=None):
    """Pick and budget one item's random affixes.  Mirrors Loot_RollAffixes:
    shared by roll() and reforge() (Phase 7), with the RNG drawn in the same
    order as before the split, so a seeded roll() is unchanged.

    ``block``   (type, sub) pairs already on the item (a reforge's forged/gem
                properties) - an affix that would build one is not eligible.
    ``max_new`` most affixes this pick may add (downside included), or None.
    ``total_fn(props) -> value`` with ``total_cap``: also step down while the
                whole item (kept properties + these) is worth more than the cap.
    Returns (chosen [[affix_index, ladder_index]], affix-only value, budget,
    has_downside)."""
    affixes = data["affixes"]["affixes"]
    lo_n, hi_n = tier["affixes"]
    n_up = lo_n + rng.randrange(hi_n - lo_n + 1)
    chosen = []          # [affix_index, ladder_index]
    used = set()

    def ok(a, role):
        return (eligible(a, cat, level, role, used)
                and (a["type"], a.get("sub") or 0) not in block)

    has_down = False
    if rng.randrange(1000) < tier.get("downside_chance", 0) and (max_new is None or max_new >= 2):
        pool = [i for i, a in enumerate(affixes) if ok(a, "downside")]
        i = weighted(rng, pool, lambda k: affixes[k]["weight"])
        if i is not None:
            lo, hi = affix_window(affixes[i], level)
            chosen.append([i, lo + rng.randrange(hi - lo + 1)])
            used.add(affixes[i]["group"])
            has_down = True
            n_up += 1

    bias = tier.get("roll_bias", 0)
    for _ in range(n_up):
        if max_new is not None and len(chosen) >= max_new:
            break
        pool = [i for i, a in enumerate(affixes) if ok(a, "upside")]
        i = weighted(rng, pool, lambda k: affixes[k]["weight"])
        if i is None:
            break
        lo, hi = affix_window(affixes[i], level)
        # roll_bias: the best of (1 + bias) rolls inside the window.
        step = lo + rng.randrange(hi - lo + 1)
        for _b in range(bias):
            step = max(step, lo + rng.randrange(hi - lo + 1))
        chosen.append([i, step])
        used.add(affixes[i]["group"])

    budget = rarity_budget(tier, level, has_down)

    def props():
        return [(affixes[i]["type"], affixes[i].get("sub") or 0,
                 affixes[i]["ladder"][k]) for i, k in chosen]

    def over(v):
        if v > budget:
            return True
        return total_fn is not None and total_fn(props()) > total_cap

    value = model.item_value(base_row, props())
    steps = 0
    while over(value) and steps < 64:
        steps += 1
        # Step the LAST upside that can still step down (to the bottom of its
        # ladder, not just of its level window: the rarity budget, not the
        # loot level, decides how strong an item is); once none can, drop the
        # last upside.  The first-rolled affix (the item's identity, its name
        # prefix) is the last to give ground.
        j = None
        for k in range(len(chosen) - 1, -1, -1):
            a = affixes[chosen[k][0]]
            if a["role"] == "upside" and chosen[k][1] > 0:
                j = k
                break
        if j is not None:
            chosen[j][1] -= 1
        else:
            ups = [k for k, (i, _) in enumerate(chosen)
                   if affixes[i]["role"] == "upside"]
            if not ups:
                break
            chosen.pop(ups[-1])
        value = model.item_value(base_row, props())
    return chosen, value, budget, has_down


def fate_bounds(value_now, count_now, value_cap, prop_cap, hw_value=0, hw_props=0):
    """The whole-item bounds a Shard of Fate reforge works under (mirrors
    Loot_FatePlan).  Each bound is the larger of the forge's cap and the item's
    HIGH-WATER mark - the largest value / counted-enchantment total the item has
    had when a Shard worked it (LOOT_FATE_HW_VALUE / _PROPS, stamped on every
    committed reforge and never lowered), or its state now when that is larger.
    Bounding by the state *now* instead was the lo-fate-ratchet defect: a cheap
    roll lowered the next reforge's bound, so an over-cap item could only shrink
    until the smith said "no room left".

    Returns (value_max, slot_max, hw_value, hw_props); the last two are what a
    committed reforge stamps."""
    hwv = max(int(hw_value or 0), int(value_now))
    hwp = max(int(hw_props or 0), int(count_now))
    return max(hwv, int(value_cap)), max(hwp, int(prop_cap)), hwv, hwp


def reforge(data, base_row, level, rarity, kept_props=(), rng=None, model=None,
            value_cap=None, prop_cap=None, kept_counted=None):
    """Phase 7: a Shard of Fate re-roll of a rolled item's random affixes.
    Mirrors Loot_Reforge.  ``kept_props`` = the (type, sub, cost) properties
    that stay (forged enchantments, gem properties); the new affixes avoid
    their (type, sub), stay inside the rarity's budget for ``level`` (the same
    budget the original roll had) and, when ``value_cap`` is given, keep the
    whole item at or under it.  ``prop_cap`` bounds kept counted + new
    affixes.  Returns a dict like roll(), or None when no upside fits (the
    game then refuses and keeps the Shard)."""
    rng = rng or random.Random()
    model = model or CostModel(data["costs"])
    level = max(1, min(MAX_LEVEL, int(level)))
    tier = data["rarity"]["tiers"][rarity]
    cat = base_category(data, base_row)
    if cat is None:
        return None
    kept = list(kept_props)
    block = frozenset((t, s) for t, s, _c in kept)
    max_new = None
    if prop_cap is not None:
        max_new = max(0, prop_cap - (len(kept) if kept_counted is None else kept_counted))
    total_fn = None
    if value_cap is not None:
        total_fn = lambda props: model.item_value(base_row, kept + props)
    chosen, value, budget, has_down = roll_affixes(
        data, cat, level, tier, base_row, rng, model, block, max_new, total_fn, value_cap)
    affixes = data["affixes"]["affixes"]
    if not any(affixes[i]["role"] == "upside" for i, _ in chosen):
        return None
    base = base_entry(data, base_row)
    return {"rarity": rarity, "level": level, "category": cat, "base": base_row,
            "affixes": [(affixes[i]["id"], affixes[i]["ladder"][k]) for i, k in chosen],
            "value": value, "budget": budget, "downside": has_down,
            "total": model.item_value(base_row, kept + [
                (affixes[i]["type"], affixes[i].get("sub") or 0, affixes[i]["ladder"][k])
                for i, k in chosen]),
            "name": item_name(base["name"] if base else str(base_row),
                              [affixes[i] for i, _ in chosen])}


def roll(data, level, floor=0, profile="lab", rng=None, model=None, wish=None):
    """One rolled item as a dict (see keys at the end).  Mirrors Loot_Roll.

    ``wish`` (Phase 6) is the beneficiary's resolved candidate list,
    ``[(base_row, weight), ...]`` from ``wish_candidates()``: with the wishlist
    chance the base is drawn from it (filtered to the profile) instead of the
    category pick.  None = no beneficiary, as for a roll with no PC."""
    rng = rng or random.Random()
    model = model or CostModel(data["costs"])
    level = max(1, min(MAX_LEVEL, int(level)))
    tiers = data["rarity"]["tiers"]
    rar = pick_rarity(data, rng, floor)
    tier = tiers[rar]

    prof = data["sources"]["profiles"][profile]
    allowed = prof.get("bases")          # optional base-row filter (e.g. belts only)

    # Named pool: a Legendary roll may award a curated existing item instead
    # (only one of a base the profile allows, when it has a filter).
    if rng.randrange(1000) < tier.get("named_chance", 0):
        n = give_named(data, level, rar, allowed, rng)
        if n:
            return n

    base = None
    if wish is not None:
        base = wish_pick(data, prof, wish, rng)
    if base is not None:
        cat = base_category(data, base["base"])
    else:
        cats = [c for c in CATEGORIES if prof["categories"].get(c, 0) > 0]
        cat = weighted(rng, cats, lambda c: prof["categories"][c])
        bases = data["bases"]["categories"][cat]
        base = weighted(rng, bases, lambda b: b["weight"] if not allowed or b["base"] in allowed else 0)

    chosen, value, budget, has_down = roll_affixes(data, cat, level, tier, base["base"],
                                                   rng, model)
    affixes = data["affixes"]["affixes"]

    unid = rng.randrange(1000) < tier.get("unidentified_chance", 0)
    slo, shi = tier.get("sockets", [0, 0])
    sockets = slo + rng.randrange(shi - slo + 1)
    return {"named": None, "sockets": sockets, "rarity": rar, "level": level, "category": cat,
            "base": base["base"], "base_name": base["name"],
            "affixes": [(affixes[i]["id"], affixes[i]["ladder"][k])
                        for i, k in chosen],
            "value": value, "budget": budget, "downside": has_down,
            "unidentified": unid,
            "name": item_name(base["name"], [affixes[i] for i, _ in chosen])}


# ---------------------------------------------------------------------------
# Phase 6: loot wishlist (sources.json "wishlist"; runtime Loot_WishPick)
# ---------------------------------------------------------------------------

WISH_AUTO_CATS = ("melee", "ranged")       # tier 1 (focus feats)
WISH_PROF_CATS = ("melee", "ranged", "caster")   # tier 2 (proficiency)


def wishlist_cfg(data):
    return data["sources"].get("wishlist", {})


def base_entry(data, row):
    for cat in CATEGORIES:
        for b in data["bases"]["categories"].get(cat, []):
            if b["base"] == row:
                return b
    return None


def base_category(data, row):
    for cat in CATEGORIES:
        if any(b["base"] == row for b in data["bases"]["categories"].get(cat, [])):
            return cat
    return None


def wish_candidates(data, wish_bases=None, feats=None, caster=False, auto=True):
    """The beneficiary's candidate list ``[(base_row, weight), ...]``.  Mirrors
    Loot_WishCands: the wishlist (uniform), else Auto tier 1 (weapon-focus
    family feats held, ``focus_weight`` each), else Auto tier 2 (every
    melee/ranged/caster base the character is proficient with, at its bases.json
    weight; a magic staff - a base with no proficiency feats in the caster
    category - only when ``caster``).  ``feats`` is the set of feat rows held;
    ``auto=False`` (the player's toggle) skips both Auto tiers."""
    if wish_bases:
        return [(b, 1) for b in wish_bases]
    if not auto:
        return []
    feats = set(feats or ())
    bi = data["costs"]["baseitems"]
    fw = wishlist_cfg(data).get("focus_weight", 1)
    out = []
    for cat in WISH_AUTO_CATS:
        for b in data["bases"]["categories"][cat]:
            n = sum(1 for f in bi[str(b["base"])].get("focus_feats", []) if f in feats)
            if n:
                out.append((b["base"], n * fw))
    if out:
        return out
    for cat in WISH_PROF_CATS:
        for b in data["bases"]["categories"][cat]:
            req = bi[str(b["base"])].get("req_feats", [])
            if cat == "caster" and not caster:
                continue
            if not req or any(f in feats for f in req):
                out.append((b["base"], b["weight"]))
    return out


def wish_pick(data, prof, wish, rng):
    """A bases.json entry drawn from ``wish`` for this profile, or None (the
    chance missed, or no candidate fits the profile).  Mirrors Loot_WishPick."""
    if rng.randrange(1000) >= wishlist_cfg(data).get("chance", 0):
        return None
    allowed = prof.get("bases")
    fits = [(row, w) for row, w in wish
            if prof["categories"].get(base_category(data, row) or "", 0) > 0
            and (not allowed or row in allowed) and w > 0]
    pick = weighted(rng, fits, lambda x: x[1])
    return base_entry(data, pick[0]) if pick else None


def validate_wishlist(data):
    errs = []
    wl = data["sources"].get("wishlist")
    if not isinstance(wl, dict):
        return ["sources.json: missing the \"wishlist\" block (Phase 6)"]
    p = wl.get("picks")
    if not isinstance(p, int) or not 1 <= p <= 10:
        errs.append("sources.json wishlist: picks must be an int 1..10")
    c = wl.get("chance")
    if not isinstance(c, int) or not 0 <= c <= 1000:
        errs.append("sources.json wishlist: chance must be a per-mille int 0..1000")
    fw = wl.get("focus_weight")
    if not isinstance(fw, int) or fw < 1:
        errs.append("sources.json wishlist: focus_weight must be an int >= 1")
    bi = data["costs"]["baseitems"]
    for cat in WISH_PROF_CATS:
        for b in data["bases"]["categories"][cat]:
            ent = bi.get(str(b["base"]), {})
            if "focus_feats" not in ent or "req_feats" not in ent:
                errs.append("_costs.json: base %d has no focus_feats/req_feats - run "
                            "gen-loot-tables.py --refresh-costs" % b["base"])
    if "caster_classes" not in data["costs"]:
        errs.append("_costs.json: no caster_classes - run gen-loot-tables.py --refresh-costs")
    return errs


# ---------------------------------------------------------------------------
# Phase 7: the Shard of Fate (loot/tokens.json "fate")
# ---------------------------------------------------------------------------

FATE_BASE_ITEM = 29        # miscmedium: non-equippable, the inert-token base


def tokens_cfg(data):
    return (data.get("tokens") or {}).get("fate") or {}


def validate_tokens(data):
    errs = []
    f = tokens_cfg(data)
    if not f:
        return ["tokens.json: missing the \"fate\" block (Phase 7, the Shard of Fate)"]
    res = f.get("resref")
    if not isinstance(res, str) or not 1 <= len(res) <= 16:
        errs.append("tokens.json fate: resref must be a 1..16 character string")
    else:
        u = load_uti(res)
        if u is None:
            errs.append("tokens.json fate: no blueprint unpacked/%s.uti.json" % res)
        else:
            if gff(u, "BaseItem") != FATE_BASE_ITEM:
                errs.append("%s: BaseItem must be %d (miscmedium, non-equippable)"
                            % (res, FATE_BASE_ITEM))
            if gff(u, "Tag") != res:
                errs.append("%s: Tag must equal the resref (scripts find it by tag)" % res)
            if int(gff(u, "Plot", 0) or 0) != 1:
                errs.append("%s: must be Plot (tradeable, never sold to a store)" % res)
            if int(gff(u, "Cursed", 0) or 0):
                errs.append("%s: must not be Cursed (it is meant to be traded)" % res)
            if int(gff(u, "StackSize", 1) or 1) != 1:
                errs.append("%s: StackSize must be 1" % res)
            if gff(u, "PropertiesList", []):
                errs.append("%s: must carry no item properties (an inert token)" % res)
        # The merit shop's reward 305 hard-codes the resref (merit_redeem.nss
        # does not include the loot tables) - keep the two in step.
        mr = UNPACKED / "merit_redeem.nss"
        if mr.exists() and ('MERIT_FATE_SHARD = "%s"' % res) not in mr.read_text(errors="replace"):
            errs.append("merit_redeem.nss: MERIT_FATE_SHARD must be \"%s\" (tokens.json "
                        "fate.resref)" % res)
    for key, lo, hi in (("boss_chance", 0, 1000), ("bonus_timeout_s", 10, 600),
                        ("lockout_s", 0, 7 * 86400)):
        v = f.get(key)
        if not isinstance(v, int) or not lo <= v <= hi:
            errs.append("tokens.json fate: %s must be an int %d..%d" % (key, lo, hi))
    if f.get("bonus_profile") not in data["sources"]["profiles"]:
        errs.append("tokens.json fate: bonus_profile %r is not a sources.json profile"
                    % f.get("bonus_profile"))
    return errs


def give_named(data, level, rarity, allowed, rng):
    """A named-pool award inside its level window, or None.  Mirrors
    Loot_GiveNamed(): the Legendary named branch of roll() and a boss's
    separate named roll (Phase 4) both come through here."""
    pool = [n for n in data["named"]["items"]
            if n["min_level"] <= level <= n["max_level"]
            and (not allowed or named_base(n["resref"]) in allowed)]
    n = weighted(rng, pool, lambda x: x.get("weight", 1))
    if not n:
        return None
    return {"named": n["resref"], "rarity": rarity, "level": level,
            "affixes": [], "value": None, "unidentified": False,
            "downside": False, "sockets": item_sockets(data, n["resref"])}


def rarity_dist(data, floor):
    """Exact probability of each rarity index for a roll at ``floor``
    (weights, then the floor, then the upgrade chances) - pick_rarity()'s law."""
    tiers = data["rarity"]["tiers"]
    total = float(sum(t["weight"] for t in tiers))
    out = [0.0] * len(tiers)
    for i, t in enumerate(tiers):
        p = t["weight"] / total
        idx = max(i, floor)
        u2 = tiers[idx].get("upgrade_two", 0) / 1000.0
        u1 = tiers[idx].get("upgrade_one", 0) / 1000.0
        top = len(tiers) - 1
        out[min(idx + 2, top)] += p * u2
        out[min(idx + 1, top)] += p * u1
        out[idx] += p * (1.0 - u1 - u2)
    return out


def named_base(resref):
    """BaseItem row of a named-pool item (its unpacked .uti), or None."""
    u = load_uti(resref)
    return None if u is None else gff(u, "BaseItem")


def item_name(base_name, chosen_affixes):
    ups = [a for a in chosen_affixes if a["role"] == "upside"]
    name = base_name
    if ups:
        name = ups[0]["prefix"] + " " + name
    if len(ups) > 1:
        name = name + " of " + ups[1]["suffix"]
    return name


# --------------------------------------------------------------------------
# Container contents (Phase 3) -- mirrors Loot_FillContainer() in loot_inc.nss
# --------------------------------------------------------------------------

PROFILE_DEFAULTS = {"rolls": 1, "rarity_floor": 0, "gear_chance": 1000,
                    "gold_pct": 0, "gem_chance": 0, "consumables": [0, 0],
                    "socket_gem_chance": 0}


def prof_get(prof, key):
    return prof.get(key, PROFILE_DEFAULTS[key])


def gold_mean(data, prof, level):
    """Mean gold of one fill: gold_pct % of the Common budget at the level."""
    return rarity_budget(data["rarity"]["tiers"][0], level) * int(prof_get(prof, "gold_pct")) // 100


def pay_gems(data, value, rng):
    """Up to 3 treasure gems worth at most ``value``; the rest is gold.

    Each pick is uniform among the gems worth between a quarter of what is
    left and all of it; when none is, the most valuable gem that still fits."""
    gems = data["treasure"]["gems"]
    out = []
    left = value
    for _ in range(3):
        pool = [g for g in gems if g["value"] <= left and g["value"] * 4 >= left]
        if pool:
            g = pool[rng.randrange(len(pool))]
        else:
            fit = [g for g in gems if g["value"] <= left]
            if not fit:
                break
            g = max(fit, key=lambda x: x["value"])   # first of the highest, as NWScript
        out.append((g["resref"], g["value"]))
        left -= g["value"]
    return out, left


def pick_consumable(data, level, rng):
    pool = [c for c in data["consumables"]["items"]
            if c["min_level"] <= level <= c["max_level"]]
    c = weighted(rng, pool, lambda x: x.get("weight", 1))
    if c is None:
        return None
    lo, hi = c.get("stack", [1, 1])
    return (c["resref"], lo + rng.randrange(hi - lo + 1))


def chest_contents(data, level, profile, rng=None, model=None):
    """One fill of a container with ``profile`` at loot level ``level``."""
    rng = rng or random.Random()
    level = max(1, min(MAX_LEVEL, int(level)))
    prof = data["sources"]["profiles"][profile]
    out = {"gear": [], "gold": 0, "gems": [], "consumables": [], "socket_gems": []}
    for _ in range(int(prof_get(prof, "rolls"))):
        if rng.randrange(1000) < int(prof_get(prof, "gear_chance")):
            out["gear"].append(roll(data, level, int(prof_get(prof, "rarity_floor")),
                                    profile, rng, model))
    mean = gold_mean(data, prof, level)
    if mean > 0:
        gold = mean // 2 + rng.randrange(mean + 1)
        if rng.randrange(1000) < int(prof_get(prof, "gem_chance")):
            out["gems"], gold = pay_gems(data, gold, rng)
        out["gold"] = gold
    lo, hi = prof_get(prof, "consumables")
    n = lo + rng.randrange(hi - lo + 1) if hi >= lo else 0
    for _ in range(n):
        c = pick_consumable(data, level, rng)
        if c:
            out["consumables"].append(c)
    # Phase 5: one socket gem, after everything else (Loot_FillContainer order).
    if rng.randrange(1000) < int(prof_get(prof, "socket_gem_chance")):
        g = gem_drop(data, level, 0, rng)
        if g:
            out["socket_gems"].append(g)
    return out


# --------------------------------------------------------------------------
# Creature drops (Phase 4) -- mirrors loot_ondeath.nss
# --------------------------------------------------------------------------

CREATURE_CLASSES = ("normal", "elite", "boss")


def creatures_cfg(data):
    return data["sources"].get("creatures", {})


def boss_resrefs():
    """{resref: canonical} for every registered boss and alias (brd_db.nss)."""
    import boss_index
    bosses, aliases = boss_index.boss_registry(UNPACKED)
    out = {b["resref"]: b["resref"] for b in bosses}
    out.update(aliases)
    return out


def creature_class(data, resref, cr, area_level, is_boss):
    """"normal" / "elite" / "boss", or None when the creature never drops.
    Mirrors the class step of loot_ondeath.nss (which also requires a hostile
    faction for normal and elite - creature_slots() already filters that).  area_level 0/None = the area
    has no loot level, so only elite_include can make the creature elite."""
    c = creatures_cfg(data)
    if resref in c.get("exclude", {}):
        return None
    if is_boss:
        return "boss"
    if resref in c.get("elite_include", {}):
        return "elite"
    if resref in c.get("elite_exclude", {}):
        return "normal"
    if area_level and level_for_cr(data["levels"], cr) >= area_level + int(c.get("elite_margin", 5)):
        return "elite"
    return "normal"


def creature_level(data, resref, cr, is_boss, bosses=None):
    """Loot level a creature's drop rolls at: a boss's levels.json
    boss_overrides entry (by canonical resref), else its own CR level."""
    if is_boss:
        bosses = bosses if bosses is not None else boss_resrefs()
        ov = data["levels"].get("boss_overrides", {}).get(bosses.get(resref, resref))
        if ov:
            return int(ov)
    return level_for_cr(data["levels"], cr)


def creature_rolls(data, cls, cr):
    """Gear rolls a drop makes when it happens: the class profile's rolls, +1
    for a boss at CR >= extra_roll_cr."""
    cfg = creatures_cfg(data)["classes"][cls]
    n = int(prof_get(data["sources"]["profiles"][cfg["profile"]], "rolls"))
    if cls == "boss" and cfg.get("extra_roll_cr") and cr >= cfg["extra_roll_cr"]:
        n += 1
    return n


CHAMPION_KEYS = {"_doc": None, "chance": (0, 1000), "min_chance": (0, 1000), "density_cap": (1, 1000),
                 "hp_pct": (0, 1000), "ab": (0, 20), "damage": (0, 20), "ac": (0, 20),
                 "saves": (0, 20), "name_prefix": None}


def champions_cfg(data):
    return creatures_cfg(data).get("champions", {})


def champion_chance(data, natural_elites, slots):
    """Per-mille chance a normal creature in an area becomes a champion:
    ``chance`` with no natural elites, falling linearly with the area's natural
    elite share (per mille of its normal+elite slots) to ``min_chance`` at
    ``density_cap``.  Mirrors LootD_AreaChampion (precomputed per area)."""
    c = champions_cfg(data)
    if not slots:
        return int(c["chance"])
    d = 1000.0 * natural_elites / slots
    return max(int(c["min_chance"]), int(round(c["chance"] * (1 - d / c["density_cap"]))))


def area_champion_chances(data):
    """{area: per-mille champion chance} for every area with normal/elite slots."""
    alv = {a: (e.get("level") or 0) for a, e in data["area_levels"]["areas"].items()}
    bosses = boss_resrefs()
    tally = {}
    for s in creature_slots():
        if s["resref"] in bosses:
            continue
        cls = creature_class(data, s["resref"], s["cr"], alv.get(s["area"], 0), False)
        if cls is None:
            continue
        t = tally.setdefault(s["area"], [0, 0])
        t[1] += 1
        t[0] += cls == "elite"
    return {a: champion_chance(data, e, n) for a, (e, n) in sorted(tally.items())}


def creature_drop(data, cls, cr, level, rng=None, model=None):
    """What one kill of a ``cls`` creature leaves on the corpse (a list of
    roll() dicts, empty when the drop chance misses).  Mirrors loot_ondeath."""
    rng = rng or random.Random()
    cfg = creatures_cfg(data)["classes"][cls]
    out = []
    if rng.randrange(1000) < int(cfg["chance"]):
        prof = data["sources"]["profiles"][cfg["profile"]]
        floor = int(prof_get(prof, "rarity_floor"))
        out = [roll(data, level, floor, cfg["profile"], rng, model)
               for _ in range(creature_rolls(data, cls, cr))]
        if rng.randrange(1000) < int(cfg.get("named_chance", 0)):
            n = give_named(data, level, len(data["rarity"]["tiers"]) - 1, prof.get("bases"), rng)
            if n:
                out.append(n)
    # Phase 5: a socket gem, rolled independently of the gear chance.
    if rng.randrange(1000) < int(cfg.get("gem_chance", 0)):
        g = gem_drop(data, level, int(data["gems"].get("boss_floor", 0)) if cls == "boss" else 0, rng)
        if g:
            out.append({"gem": g})
    # Phase 7: a boss may drop a Shard of Fate (tokens.json fate.boss_chance).
    if cls == "boss" and rng.randrange(1000) < int(tokens_cfg(data).get("boss_chance", 0)):
        out.append({"shard": True})
    return out


def validate_creatures(data):
    """Phase 4 rules for sources.json "creatures" and levels.json boss_overrides."""
    errs = []
    c = creatures_cfg(data)
    profiles = data["sources"]["profiles"]
    if not c:
        return ["sources.json: the \"creatures\" block (Phase 4 creature drops) is missing"]
    m = c.get("elite_margin")
    if not isinstance(m, int) or not 1 <= m <= MAX_LEVEL:
        errs.append("sources.json creatures: elite_margin must be an int 1..%d" % MAX_LEVEL)
    classes = c.get("classes", {})
    if set(classes) != set(CREATURE_CLASSES):
        errs.append("sources.json creatures: classes must be exactly %s" % ", ".join(CREATURE_CLASSES))
    for name, cfg in classes.items():
        tag = "sources.json creatures class %s" % name
        if cfg.get("profile") not in profiles:
            errs.append("%s: unknown profile %r" % (tag, cfg.get("profile")))
        for k in ("chance", "named_chance", "gem_chance"):
            v = cfg.get(k, 0)
            if not isinstance(v, int) or not 0 <= v <= 1000:
                errs.append("%s: %s must be an int 0..1000 (per mille)" % (tag, k))
        v = cfg.get("extra_roll_cr", 0)
        if not isinstance(v, int) or v < 0:
            errs.append("%s: extra_roll_cr must be a non-negative int" % tag)
        if name != "boss" and (cfg.get("named_chance") or cfg.get("extra_roll_cr")):
            errs.append("%s: named_chance and extra_roll_cr are boss-only" % tag)
        extra = set(cfg) - {"chance", "profile", "named_chance", "extra_roll_cr", "gem_chance"}
        if extra:
            errs.append("%s: unknown key(s) %s" % (tag, ", ".join(sorted(extra))))
    seen = {}
    for key in ("elite_include", "elite_exclude", "exclude"):
        for rr, why in c.get(key, {}).items():
            tag = "sources.json creatures %s %s" % (key, rr)
            if not (UNPACKED / (rr + ".utc.json")).exists():
                errs.append("%s: no unpacked/%s.utc.json" % (tag, rr))
            if not isinstance(why, str) or not why.strip():
                errs.append("%s: give a reason" % tag)
            if '"' in rr or "\\" in rr or len(rr) > 16:
                errs.append("%s: not a resref" % tag)
            if rr in seen:
                errs.append("%s: also listed in %s" % (tag, seen[rr]))
            seen[rr] = key
    ch = c.get("champions")
    if not isinstance(ch, dict):
        errs.append("sources.json creatures: the \"champions\" block is missing")
    else:
        for k in set(ch) - set(CHAMPION_KEYS):
            errs.append("sources.json creatures champions: unknown key %r" % k)
        for k, rng_ in CHAMPION_KEYS.items():
            if rng_ is None:
                continue
            v = ch.get(k)
            if not isinstance(v, int) or isinstance(v, bool) or not rng_[0] <= v <= rng_[1]:
                errs.append("sources.json creatures champions: %s must be an int %d..%d" % (k, rng_[0], rng_[1]))
        if isinstance(ch.get("min_chance"), int) and isinstance(ch.get("chance"), int) \
                and ch["min_chance"] > ch["chance"]:
            errs.append("sources.json creatures champions: min_chance is above chance")
        np_ = ch.get("name_prefix")
        if not isinstance(np_, str) or not np_.strip() or '"' in np_ or "\\" in np_:
            errs.append("sources.json creatures champions: name_prefix must be a plain non-empty string")
    bosses = boss_resrefs()
    for rr, lvl in data["levels"].get("boss_overrides", {}).items():
        tag = "levels.json boss_overrides %s" % rr
        if rr not in bosses:
            errs.append("%s: not a registered boss (brd_db.nss)" % tag)
        if not isinstance(lvl, int) or not 1 <= lvl <= MAX_LEVEL:
            errs.append("%s: level must be an int 1..%d" % (tag, MAX_LEVEL))
    return errs


def item_facts(data, resref):
    """{base, cost, stack, plot, cursed, props, name} of a local or stock item."""
    u = load_uti(resref)
    if u is not None:
        return {"base": gff(u, "BaseItem"), "cost": int(gff(u, "Cost", 0) or 0),
                "stack": int(gff(u, "StackSize", 1) or 1),
                "plot": int(gff(u, "Plot", 0) or 0), "cursed": int(gff(u, "Cursed", 0) or 0),
                "props": len(gff(u, "PropertiesList", []) or []), "local": True}
    f = data.get("items", {}).get("items", {}).get(resref)
    if f:
        return dict(f, local=False)
    return None


# --------------------------------------------------------------------------
# Validation -- what tests/check_loot_tables.py fails the repack on
# --------------------------------------------------------------------------

def validate(data, item_index=None):
    """Return a list of error strings (empty = good)."""
    errs = []
    costs = data["costs"]
    model = CostModel(costs)
    tiers = data["rarity"]["tiers"]

    # -- rarity
    if len(tiers) != 5:
        errs.append("rarity.json: expected 5 tiers, found %d" % len(tiers))
    for i, t in enumerate(tiers):
        tag = "rarity %s" % t.get("id", i)
        if t.get("color") not in RARITY_COLORS:
            errs.append("%s: color %r is not a color.nss constant" % (tag, t.get("color")))
        lo, hi = t["affixes"]
        if not (0 <= lo <= hi):
            errs.append("%s: affixes range %r" % (tag, t["affixes"]))
        extra = 2 if t.get("downside_chance", 0) > 0 else 0
        if hi + extra > FORGE_LEGAL_MAX_PROPS:
            errs.append("%s: up to %d properties (%d affixes + downside + its "
                        "bonus upside) exceeds the forge ceiling of %d"
                        % (tag, hi + extra, hi, FORGE_LEGAL_MAX_PROPS))
        pts = curve(t["budget"])
        if pts[0][0] != 1 or pts[-1][0] != MAX_LEVEL:
            errs.append("%s: budget curve must start at level 1 and end at %d"
                        % (tag, MAX_LEVEL))
        if any(b[1] < a[1] for a, b in zip(pts, pts[1:])):
            errs.append("%s: budget curve decreases" % tag)
        if not isinstance(t.get("roll_bias", 0), int) or not 0 <= t.get("roll_bias", 0) <= 3:
            errs.append("%s: roll_bias must be an int 0..3" % tag)
        for k in ("weight", "downside_chance", "unidentified_chance",
                  "upgrade_one", "upgrade_two", "named_chance"):
            v = t.get(k, 0)
            if not isinstance(v, int) or v < 0 or (k != "weight" and v > 1000):
                errs.append("%s: %s must be an int (per-mille for chances)" % (tag, k))
        if i and t.get("named_chance", 0) and i != len(tiers) - 1:
            errs.append("%s: only the top tier may award named items" % tag)
    for lvl in (1, 20, 40, 60):
        b = [rarity_budget(t, lvl) for t in tiers]
        if b != sorted(b):
            errs.append("rarity budgets at level %d are not non-decreasing by tier: %r"
                        % (lvl, b))

    # -- levels
    pts = data["levels"]["cr_points"]
    if any(b[0] <= a[0] or b[1] < a[1] for a, b in zip(pts, pts[1:])):
        errs.append("levels.json: cr_points must rise in CR and never fall in level")
    if pts[0][1] < 1 or pts[-1][1] > MAX_LEVEL:
        errs.append("levels.json: loot levels must stay within 1..%d" % MAX_LEVEL)
    ap = data["levels"].get("area_percentile", DEFAULT_AREA_PERCENTILE)
    if not isinstance(ap, int) or isinstance(ap, bool) or not 1 <= ap <= 100:
        errs.append("levels.json: area_percentile must be an integer in 1..100")

    # -- bases
    seen_base = set()
    for cat, bases in data["bases"]["categories"].items():
        if cat not in CATEGORIES:
            errs.append("bases.json: unknown category %r" % cat)
        for b in bases:
            row = b["base"]
            tag = "bases.json %s/%s" % (cat, b.get("name"))
            if row in seen_base:
                errs.append("%s: base row %d listed twice" % (tag, row))
            seen_base.add(row)
            bi = costs["baseitems"].get(str(row))
            if not bi:
                errs.append("%s: baseitems.2da row %d missing from _costs.json "
                            "(re-run gen-loot-tables.py --refresh-costs)" % (tag, row))
                continue
            if not (UNPACKED / ("forge_blank_%d.uti.json" % row)).exists():
                errs.append("%s: no forge_blank_%d blank to build from" % (tag, row))
            if int(bi.get("stacking") or 1) > 1:
                errs.append("%s: stackable base items cannot be rolled" % tag)
            mt = bi.get("model_type")
            want = {0: 1, 1: 1, 2: 3, 3: len(ARMOR_PARTS)}.get(mt)
            if not b.get("donors"):
                errs.append("%s: no appearance donors (gen-loot-tables.py --harvest-donors)" % tag)
            for dn in b.get("donors", []):
                if want is None or len(dn) != want:
                    errs.append("%s: donor %r does not fit model type %r" % (tag, dn, mt))
                    break
    for cat in CATEGORIES:
        if not data["bases"]["categories"].get(cat):
            errs.append("bases.json: category %r has no bases" % cat)

    # -- affixes
    ids = set()
    for i, a in enumerate(data["affixes"]["affixes"]):
        tag = "affix %s" % a.get("id", i)
        if a.get("id") in ids:
            errs.append("%s: duplicate id" % tag)
        ids.add(a.get("id"))
        t = a.get("type")
        if t not in SUPPORTED_IP:
            errs.append("%s: item property type %r is not in SUPPORTED_IP" % (tag, t))
            continue
        if t in BANNED["type"]:
            errs.append("%s: %s is banned from loot" % (tag, BANNED["type"][t]))
        d = costs["itempropdef"].get(str(t), {})
        sub = a.get("sub")
        st = d.get("subtype_table")
        if st:
            if sub is None or str(sub) not in costs["subtype_rows"].get(st, []):
                errs.append("%s: subtype %r is not a row of %s" % (tag, sub, st))
        elif sub is not None:
            errs.append("%s: %s takes no subtype" % (tag, SUPPORTED_IP[t][0]))
        if t in (16, 20, 23, 24) and sub in BANNED["damage_type_sub"]:
            errs.append("%s: %s is banned from loot" % (tag, BANNED["damage_type_sub"][sub]))
        if t == 37 and sub in BANNED["immunity_misc_sub"]:
            errs.append("%s: %s is banned from loot" % (tag, BANNED["immunity_misc_sub"][sub]))
        ct = d.get("cost_table")
        ladder = a.get("ladder") or []
        if not ladder:
            errs.append("%s: empty ladder" % tag)
        if ct:
            rows = costs["cost_tables"].get(ct, {})
            for c in ladder:
                if str(c) not in rows:
                    errs.append("%s: cost %r is not a row of %s" % (tag, c, ct))
        elif any(c != 0 for c in ladder):
            errs.append("%s: %s has no cost table; ladder must be [0]" % (tag, SUPPORTED_IP[t][0]))
        w = a.get("window", {})
        if "1" not in w or str(MAX_LEVEL) not in w:
            errs.append("%s: window needs levels 1 and %d" % (tag, MAX_LEVEL))
        for k, (lo, hi) in w.items():
            if not (0 <= lo <= hi < len(ladder)):
                errs.append("%s: window %s=%r outside ladder of %d" % (tag, k, [lo, hi], len(ladder)))
        if a.get("role") not in ("upside", "downside"):
            errs.append("%s: role must be upside or downside" % tag)
        if (a.get("role") == "downside") != (t in NEGATIVE_TYPES):
            errs.append("%s: role %r does not match the property's sign" % (tag, a.get("role")))
        if a.get("role") == "upside" and not (a.get("prefix") and a.get("suffix")):
            errs.append("%s: upside affixes need a prefix and a suffix" % tag)
        for c in a.get("cats", []):
            if c not in CATEGORIES:
                errs.append("%s: unknown category %r" % (tag, c))
        if not isinstance(a.get("weight"), int) or not a.get("group"):
            errs.append("%s: needs an int weight and a group" % tag)
        for s in (a.get("prefix", ""), a.get("suffix", "")):
            if '"' in s or "\\" in s or not s.isascii():
                errs.append("%s: name words must be plain ASCII without quotes" % tag)

    # -- per-tier reachability: the cheapest legal set of `min` affixes must fit
    affixes = data["affixes"]["affixes"]
    for t in tiers:
        need = t["affixes"][0]
        if need == 0:
            continue
        for lvl in (1, 20, 40, 60):
            budget = rarity_budget(t, lvl)
            for cat in CATEGORIES:
                pool = [a for a in affixes if eligible(a, cat, lvl, "upside", set())]
                by_group = {}
                for a in pool:
                    c = model.prop_cost(a["type"], a.get("sub") or 0, a["ladder"][0])
                    g = a["group"]
                    if g not in by_group or c < by_group[g][0]:
                        by_group[g] = (c, a)
                cheap = sorted(by_group.values(), key=lambda x: x[0])[:need]
                if len(cheap) < need:
                    errs.append("rarity %s level %d: category %s has only %d affix "
                                "groups, needs %d" % (t["id"], lvl, cat, len(cheap), need))
                    continue
                bases = data["bases"]["categories"].get(cat, [])
                if not bases:
                    continue
                b = min(bases, key=lambda x: model.base_cost(x["base"]))
                v = model.item_value(b["base"], [
                    (a["type"], a.get("sub") or 0, a["ladder"][0]) for _, a in cheap])
                if v > budget:
                    errs.append("rarity %s level %d: cheapest %d-affix %s item is "
                                "worth %d gp, over the %d gp budget"
                                % (t["id"], lvl, need, cat, v, budget))

    # -- named pool
    for n in data["named"]["items"]:
        rr = n["resref"]
        u = load_uti(rr)
        tag = "named %s" % rr
        if u is None:
            errs.append("%s: no unpacked/%s.uti.json" % (tag, rr))
            continue
        if gff(u, "Plot", 0) or gff(u, "Cursed", 0):
            errs.append("%s: Plot or Cursed items cannot be loot" % tag)
        if int(gff(u, "StackSize", 1) or 1) != 1:
            errs.append("%s: stacked items cannot be loot" % tag)
        if not (1 <= n["min_level"] <= n["max_level"] <= MAX_LEVEL):
            errs.append("%s: level window %r..%r" % (tag, n["min_level"], n["max_level"]))
        if len(rr) > 16:
            errs.append("%s: resref longer than 16 characters" % tag)

    # -- sources
    for name, p in data["sources"]["profiles"].items():
        if len(name) > 16 or not name.replace("_", "").isalnum():
            errs.append("sources.json: profile name %r must be <=16 [a-z0-9_]" % name)
        for c, w in p["categories"].items():
            if c not in CATEGORIES or not isinstance(w, int) or w < 0:
                errs.append("sources.json %s: bad category weight %r=%r" % (name, c, w))
        if not 0 <= p.get("rarity_floor", 0) < len(tiers):
            errs.append("sources.json %s: rarity_floor out of range" % name)
        for k in ("rolls", "gear_chance", "gold_pct", "gem_chance", "socket_gem_chance"):
            v = prof_get(p, k)
            if not isinstance(v, int) or v < 0 or (k.endswith("chance") and v > 1000):
                errs.append("sources.json %s: %s must be a non-negative int%s"
                            % (name, k, " (per-mille)" if k.endswith("chance") else ""))
        allowed = p.get("bases")
        if allowed is not None:
            rows = {b["base"]: cat for cat, lst in data["bases"]["categories"].items() for b in lst}
            if not (isinstance(allowed, list) and allowed and all(isinstance(x, int) for x in allowed)):
                errs.append("sources.json %s: bases must be a non-empty list of base-item rows" % name)
            else:
                for x in allowed:
                    if x not in rows:
                        errs.append("sources.json %s: base row %r is not in bases.json" % (name, x))
                    elif not p["categories"].get(rows[x]):
                        errs.append("sources.json %s: base row %r is in category %s, which the "
                                    "profile does not roll" % (name, x, rows[x]))
                for cat, wgt in p["categories"].items():
                    if wgt and not any(rows.get(x) == cat for x in allowed):
                        errs.append("sources.json %s: category %s has none of the allowed bases "
                                    "(the roll would fail)" % (name, cat))
        c = prof_get(p, "consumables")
        if not (isinstance(c, list) and len(c) == 2 and all(isinstance(x, int) for x in c)
                and 0 <= c[0] <= c[1] <= 10):
            errs.append("sources.json %s: consumables must be [min, max] ints, 0..10" % name)
    if "lab" not in data["sources"]["profiles"]:
        errs.append("sources.json: the 'lab' profile (Loot Lab) is required")
    errs.extend(validate_containers(data))
    errs.extend(validate_creatures(data))
    errs.extend(validate_gems(data))
    errs.extend(validate_wishlist(data))
    errs.extend(validate_tokens(data))

    # -- sanity ceiling against the module's own obtainable gear
    if item_index is not None:
        top = max((int(float(i.get("cost_gp") or 0)) for i in item_index
                   if i.get("accessible")), default=0)
        b = rarity_budget(tiers[-1], MAX_LEVEL, True)
        if top and b > top:
            errs.append("top-tier budget at level %d (%d gp) exceeds the most valuable "
                        "obtainable item (%d gp)" % (MAX_LEVEL, b, top))
    return errs


SCRIPT_MODES = ("refill", "once", "custom")


def validate_containers(data, area_doc=None):
    """Phase 3 rules: the script table, area levels and the two item pools."""
    errs = []
    src = data["sources"]
    profiles = src["profiles"]
    for name, ent in src.get("scripts", {}).items():
        tag = "sources.json script %s" % name
        if len(name) > 16 or name != name.lower() or not name.replace("_", "").isalnum():
            errs.append("%s: script names are <=16 lowercase [a-z0-9_]" % tag)
        if ent.get("profile") not in profiles:
            errs.append("%s: unknown profile %r" % (tag, ent.get("profile")))
        if ent.get("mode") not in SCRIPT_MODES:
            errs.append("%s: mode must be one of %s" % (tag, "/".join(SCRIPT_MODES)))
        if ent.get("mode") == "custom":
            # Hand-written (e.g. the Setti coffers' cooldown): it must exist and
            # name its profile, so the table and the script cannot drift apart.
            sp = UNPACKED / (name + ".nss")
            if not sp.exists():
                errs.append("%s: custom script unpacked/%s.nss does not exist" % (tag, name))
            elif '"%s"' % ent.get("profile") not in sp.read_text(errors="replace"):
                errs.append("%s: custom script does not use its profile \"%s\""
                            % (tag, ent.get("profile")))
    for a, ent in src.get("area_overrides", {}).items():
        tag = "sources.json area_overrides %s" % a
        if not (UNPACKED / (a + ".are.json")).exists():
            errs.append("%s: no such area" % tag)
        if not isinstance(ent.get("level"), int) or not 1 <= ent["level"] <= MAX_LEVEL:
            errs.append("%s: level must be an int 1..%d" % (tag, MAX_LEVEL))
        if not ent.get("reason"):
            errs.append("%s: give a reason" % tag)
    doc = area_doc if area_doc is not None else area_levels_doc(data)
    for a, ent in doc["areas"].items():
        if ent["chests"] and ent["level"] is None:
            errs.append("area %s has %d treasure container(s) but no hostile creatures to "
                        "set its loot level - add it to sources.json area_overrides "
                        "(gen-area-loot-levels.py --suggest proposes one)" % (a, ent["chests"]))

    for c in data["consumables"]["items"]:
        rr = c.get("resref", "")
        tag = "consumables.json %s" % rr
        f = item_facts(data, rr)
        if f is None:
            errs.append("%s: no unpacked/%s.uti.json and not in loot/_items.json "
                        "(gen-loot-consumables.py --refresh-items)" % (tag, rr))
            continue
        if f["plot"] or f["cursed"]:
            errs.append("%s: Plot or Cursed items cannot be loot" % tag)
        if len(rr) > 16:
            errs.append("%s: resref longer than 16 characters" % tag)
        if not (1 <= c.get("min_level", 0) <= c.get("max_level", 0) <= MAX_LEVEL):
            errs.append("%s: level window %r..%r" % (tag, c.get("min_level"), c.get("max_level")))
        st = c.get("stack", [1, 1])
        if not (isinstance(st, list) and len(st) == 2 and 1 <= st[0] <= st[1] <= 99):
            errs.append("%s: stack must be [min, max] within 1..99" % tag)
        if not isinstance(c.get("weight", 1), int) or not 1 <= c.get("weight", 1) <= 9999:
            errs.append("%s: weight must be an int 1..9999" % tag)
        if not rr or not rr.replace("_", "").isalnum() or rr != rr.lower():
            errs.append("%s: resref must be lowercase [a-z0-9_]" % tag)
    for lvl in (1, 20, 40, 60):
        if not any(c["min_level"] <= lvl <= c["max_level"] for c in data["consumables"]["items"]):
            if any(prof_get(p, "consumables")[1] for p in profiles.values()):
                errs.append("consumables.json: no consumable is eligible at level %d" % lvl)

    for g in data["treasure"]["gems"]:
        rr = g.get("resref", "")
        tag = "treasure.json %s" % rr
        f = item_facts(data, rr)
        if f is None:
            errs.append("%s: no unpacked/%s.uti.json and not in loot/_items.json" % (tag, rr))
            continue
        if f["plot"] or f["cursed"]:
            errs.append("%s: Plot or Cursed items cannot be treasure" % tag)
        if f["props"]:
            errs.append("%s: treasure gems must carry no item properties" % tag)
        if not isinstance(g.get("value"), int) or g["value"] < 1:
            errs.append("%s: value must be a positive int" % tag)
        if len(rr) > 16:
            errs.append("%s: resref longer than 16 characters" % tag)
    if any(prof_get(p, "gem_chance") for p in profiles.values()) and not data["treasure"]["gems"]:
        errs.append("treasure.json: a profile has gem_chance but there are no gems")
    return errs


# --------------------------------------------------------------------------
# Sockets and gems (Phase 5) -- mirrors gem_inc.nss
# --------------------------------------------------------------------------

GEM_PREFIX = "sgem_"
GEM_BASE = 24            # miscsmall: 1x1, non-equippable, stack 1 (an activated item must not be wearable)
GEM_PALETTE = 57         # itempalcus Misc > the treasure-gem category
GEM_SPELL = 329          # iprp_spells ACTIVATE_ITEM = targeted Unique Power (335 is Self Only)
# Methonash's caps (Socket-system-for-weapons): no gem may take a property past them.
GEM_CAP_DAMAGE_ROW = 13  # iprp_damagecost 2d10
GEM_CAP_HIT = 16         # Enhancement / Attack Bonus +16
HIT_TYPES = (6, 56)
PLAYER_SLOTS = 0x3FFF    # EquipableSlots bits a player can wear (above them: creature slots)


def gem_resref(fid, tier):
    return "%s%s_%d" % (GEM_PREFIX, fid, tier)


def _baseitems_2da():
    p = HAK_2DA / "baseitems.2da"
    return read_2da_text(p.read_text(encoding="latin-1"))[1] if p.exists() else {}


def damage_power():
    """{iprp_damagecost row: 2 x average damage} from hak_2da/ (the module's own
    table).  Gems place an off-ladder damage value by this, so +5 flat steps to
    1d10, never down to 1d6."""
    p = HAK_2DA / "iprp_damagecost.2da"
    out = {}
    if not p.exists():
        return out
    for row, r in read_2da_text(p.read_text(encoding="latin-1"))[1].items():
        n, d = _num(r.get("NumDice")), _num(r.get("Die"))
        if n is None or d is None:
            continue
        out[row] = int(2 * d) if n == 0 else int(n * (d + 1))
    return out


def damage_max():
    p = HAK_2DA / "iprp_damagecost.2da"
    out = {}
    if p.exists():
        for row, r in read_2da_text(p.read_text(encoding="latin-1"))[1].items():
            n, d = _num(r.get("NumDice")), _num(r.get("Die"))
            if n is not None and d is not None:
                out[row] = int(d) if n == 0 else int(n * d)
    return out


def prop_power(ptype, row, dmgpow):
    """Strength of cost row ``row`` of a property type: 2 x average damage for
    Damage Bonus, the row itself (= the bonus) for everything gems touch."""
    return dmgpow.get(row, 0) if ptype == 16 else row


def socket_base_categories(data):
    """{base row: category} of every socketable base item."""
    out = {b["base"]: cat for cat, lst in data["bases"]["categories"].items() for b in lst}
    for row, cat in data["sockets"].get("extra_bases", {}).items():
        out[int(row)] = cat
    return out


def affix_by_id(data):
    return {a["id"]: a for a in data["affixes"]["affixes"]}


def gem_families(data):
    return data["gems"].get("families", [])


def gem_fits(data, fam, cat):
    ab = affix_by_id(data)
    return any(cat in ab[a]["cats"] for a in fam["affixes"] if a in ab)


def gem_merge(data, fam, tier, props, cat, dmgpow=None):
    """What gem (fam, tier) does to an item of category ``cat`` carrying the
    permanent properties ``props`` ({(type, sub): cost row}).

    Returns (type, sub, old_row_or_None, new_row) or a refusal string.  Mirrors
    Gem_Plan in gem_inc.nss -- change one, change the other."""
    dmgpow = dmgpow if dmgpow is not None else damage_power()
    if not gem_fits(data, fam, cat):
        return "does not fit a %s item" % cat
    ab = affix_by_id(data)
    lad = fam["ladder"]
    steps = fam["steps"][tier]
    for aid in fam["affixes"]:
        a = ab[aid]
        key = (a["type"], a.get("sub") or 0)
        if key not in props:
            continue
        old = props[key]
        pw = lambda r: prop_power(a["type"], r, dmgpow)  # noqa: E731
        if old in lad:
            pos = lad.index(old)
        else:
            below = [i for i, r in enumerate(lad) if pw(r) <= pw(old)]
            pos = max(below) if below else -1
        new = min(pos + steps, len(lad) - 1)
        if new <= pos:
            return "already at the socket cap"
        if old not in lad and pw(lad[new]) <= pw(old):
            return "would not make it stronger"
        return (a["type"], key[1], old, lad[new])
    for aid in fam["affixes"]:
        a = ab[aid]
        if cat in a["cats"]:
            return (a["type"], a.get("sub") or 0, None, lad[min(steps, len(lad)) - 1])
    return "does not fit a %s item" % cat


def gem_band(data, level):
    band = None
    for b in data["gems"].get("level_bands", []):
        if level >= b["min_level"]:
            band = b
    return band or {"floor": 0, "ceiling": 0}


def gem_tier(data, level, floor, rng):
    """A gem's tier: a rarity roll at max(floor, the band's floor), capped at
    the band's ceiling.  Mirrors Gem_RollTier."""
    b = gem_band(data, level)
    return min(pick_rarity(data, rng, max(floor, b["floor"])), b["ceiling"])


def gem_drop(data, level, floor, rng):
    """(family id, tier) of one dropped gem, or None.  Mirrors Gem_Drop."""
    fams = [f for f in gem_families(data) if f.get("weight", 0) > 0]
    f = weighted(rng, fams, lambda x: x["weight"])
    if f is None:
        return None
    return (f["id"], gem_tier(data, max(1, min(MAX_LEVEL, level)), floor, rng))


def _uti_eligible(data, u, cats=None, bstack=None):
    cats = cats if cats is not None else socket_base_categories(data)
    return (gff(u, "BaseItem") in cats and not gff(u, "Plot", 0) and not gff(u, "Cursed", 0)
            and int(gff(u, "StackSize", 1) or 1) == 1)


def item_sockets(data, resref, u=None, cats=None):
    """Sockets an existing (not rolled) item gets from loot/sockets.json."""
    s = data["sockets"]
    if not s:
        return 0
    u = u if u is not None else load_uti(resref)
    if resref in s.get("exclude", {}):
        return 0
    if u is None or not _uti_eligible(data, u, cats):
        return 0                       # the runtime checks base/Plot/Cursed/stack first too
    if resref in s.get("overrides", {}):
        return int(s["overrides"][resref])
    cost = int(gff(u, "Cost", 0) or 0) + int(gff(u, "AddCost", 0) or 0)
    return int(s["two_sockets"]) if cost >= int(s["two_cost"]) else int(s["default"])


def socket_exceptions(data):
    """{resref: count} for every module item whose count the runtime cannot
    work out from the item itself (base, Plot, Cursed, stack): the two-socket
    tier, overrides and excludes.  Everything else eligible gets ``default``."""
    s = data["sockets"]
    out = {}
    cats = socket_base_categories(data)
    for p in sorted(UNPACKED.glob("*.uti.json")):
        rr = p.name[:-len(".uti.json")]
        if rr.startswith(("forge_blank_", GEM_PREFIX)):
            continue
        u = json.loads(p.read_text())
        n = item_sockets(data, rr, u, cats)
        default = int(s["default"]) if _uti_eligible(data, u, cats) else 0
        if rr in s.get("exclude", {}) or rr in s.get("overrides", {}) or n != default:
            out[rr] = n
    return out


def gem_uti(data, fam, tier):
    """The expected blueprint of gem (fam, tier) as nwn_gff JSON."""
    t = data["gems"]["tiers"][tier]
    rr = gem_resref(fam["id"], tier)
    name = "%s %s" % (t["word"], fam["stone"])
    steps = fam["steps"][tier]
    desc = ("A %s socket gem (%s). Use it on an item with an open socket: it adds %s, or "
            "raises the item's own by %d step%s, up to the socket cap. Socketing is permanent "
            "and the gem is consumed." % (data["rarity"]["tiers"][tier]["name"], name,
                                         fam["effect"], steps, "" if steps == 1 else "s"))

    def v(typ, val):
        return {"type": typ, "value": val}
    return {
        "__data_type": "UTI ",
        "AddCost": v("dword", int(t["value"])),
        "BaseItem": v("int", GEM_BASE),
        "Charges": v("byte", 0),
        "Comment": v("cexostring", "GENERATED by bin/gen-loot-tables.py from loot/gems.json. Do not edit."),
        "Cost": v("dword", int(t["value"])),
        "Cursed": v("byte", 0),
        "DescIdentified": v("cexolocstring", {"0": desc}),
        "Description": v("cexolocstring", {"0": desc}),
        "Identified": v("byte", 1),
        "LocalizedName": v("cexolocstring", {"0": name}),
        "ModelPart1": v("byte", int(fam.get("model", 0))),
        "PaletteID": v("byte", GEM_PALETTE),
        "Plot": v("byte", 0),
        "PropertiesList": v("list", [{
            "__struct_id": 0,
            "ChanceAppear": v("byte", 100),
            "CostTable": v("byte", 3),
            "CostValue": v("word", 13),
            "Param1": v("byte", 255),
            "Param1Value": v("byte", 0),
            "PropertyName": v("word", 15),
            "Subtype": v("word", GEM_SPELL)}]),
        "StackSize": v("word", 1),
        "Stolen": v("byte", 0),
        "Tag": v("cexostring", rr),
        "TemplateResRef": v("resref", rr),
    }


GEM_UTI_KEYS = ("AddCost", "BaseItem", "Cursed", "Description", "LocalizedName", "ModelPart1",
                "PaletteID", "Plot", "PropertiesList", "StackSize", "Tag", "TemplateResRef")


def gem_blueprint_problems(data):
    """(stale-or-missing resrefs, orphaned sgem_* blueprints).  Compares the
    fields that matter, not bytes, so a toolset round-trip does not trip it."""
    stale, want = [], set()
    for fam in gem_families(data):
        for tier in range(len(data["gems"].get("tiers", []))):
            rr = gem_resref(fam["id"], tier)
            want.add(rr)
            exp = gem_uti(data, fam, tier)
            cur = load_uti(rr)
            if cur is None or any(_strip_sid(cur.get(k)) != _strip_sid(exp[k]) for k in GEM_UTI_KEYS):
                stale.append(rr)
    orphans = sorted(p.name[:-len(".uti.json")] for p in UNPACKED.glob(GEM_PREFIX + "*.uti.json")
                     if p.name[:-len(".uti.json")] not in want)
    return stale, orphans


def donor_props(data):
    """Sorted (type, sub, cost row) the donor item must carry: every ladder row
    (not just the level window - the budget step-down walks the whole ladder)
    of every affix whose type is in DONOR_TYPES."""
    out = set()
    for a in data["affixes"]["affixes"]:
        if a["type"] in DONOR_TYPES:
            for row in a["ladder"]:
                out.add((a["type"], a.get("sub") or 0, row))
    return sorted(out)


def donor_uti(data):
    """The expected loot_ipdonor blueprint as nwn_gff JSON."""
    def v(typ, val):
        return {"type": typ, "value": val}
    props = [{
        "__struct_id": 0,
        "ChanceAppear": v("byte", 100),
        "CostTable": v("byte", DONOR_COST_TABLE[t]),
        "CostValue": v("word", row),
        "Param1": v("byte", 255),
        "Param1Value": v("byte", 0),
        "PropertyName": v("word", t),
        "Subtype": v("word", sub)} for t, sub, row in donor_props(data)]
    desc = ("System item: the rolled-loot engine copies item properties from it whose "
            "NWScript constructor rejects this module's extended cost rows. Lives in "
            "FORGE_VAULT; never given to players.")
    return {
        "__data_type": "UTI ",
        "AddCost": v("dword", 0),
        "BaseItem": v("int", DONOR_BASE),
        "Charges": v("byte", 0),
        "Comment": v("cexostring", "GENERATED by bin/gen-loot-tables.py from loot/affixes.json "
                                   "(loot_model.DONOR_TYPES). Do not edit."),
        "Cost": v("dword", 0),
        "Cursed": v("byte", 1),
        "DescIdentified": v("cexolocstring", {"0": desc}),
        "Description": v("cexolocstring", {"0": desc}),
        "Identified": v("byte", 1),
        "LocalizedName": v("cexolocstring", {"0": "Loot Property Donor"}),
        "ModelPart1": v("byte", 61),
        "PaletteID": v("byte", DONOR_PALETTE),
        "Plot": v("byte", 1),
        "PropertiesList": v("list", props),
        "StackSize": v("word", 1),
        "Stolen": v("byte", 0),
        "Tag": v("cexostring", DONOR_RESREF),
        "TemplateResRef": v("resref", DONOR_RESREF),
    }


DONOR_UTI_KEYS = ("BaseItem", "Cursed", "PaletteID", "Plot", "PropertiesList", "Tag",
                  "TemplateResRef")


def donor_stale(data):
    """True when unpacked/loot_ipdonor.uti.json is missing or does not carry
    exactly the properties donor_props() needs (meaningful fields only, so a
    toolset round-trip does not trip it)."""
    exp = donor_uti(data)
    cur = load_uti(DONOR_RESREF)
    return cur is None or any(_strip_sid(cur.get(k)) != _strip_sid(exp[k]) for k in DONOR_UTI_KEYS)


def _strip_sid(v):
    if isinstance(v, dict):
        return {k: _strip_sid(x) for k, x in v.items() if k not in ("__struct_id", "id")}
    if isinstance(v, list):
        return [_strip_sid(x) for x in v]
    return v


def validate_gems(data):
    """Phase 5 rules for loot/gems.json, loot/sockets.json and rarity sockets."""
    errs = []
    g = data["gems"]
    s = data["sockets"]
    if not g.get("families"):
        return ["loot/gems.json: no gem families"]
    if not s:
        return ["loot/sockets.json is missing"]
    rtiers = data["rarity"]["tiers"]
    ab = affix_by_id(data)
    costs = data["costs"]
    dmgpow, dmgmax = damage_power(), damage_max()
    if not dmgpow:
        errs.append("hak_2da/iprp_damagecost.2da is missing (gem damage ladders read it)")

    # -- sockets.json + rarity sockets
    mx = s.get("max_sockets")
    if not isinstance(mx, int) or not 1 <= mx <= 6:
        errs.append("sockets.json: max_sockets must be an int 1..6")
        mx = 6
    for k in ("version", "default", "two_sockets", "two_cost"):
        if not isinstance(s.get(k), int) or isinstance(s.get(k), bool) or s[k] < 0:
            errs.append("sockets.json: %s must be a non-negative int" % k)
    if isinstance(s.get("version"), int) and s["version"] < 1:
        errs.append("sockets.json: version starts at 1")
    for k in ("default", "two_sockets"):
        if isinstance(s.get(k), int) and s[k] > mx:
            errs.append("sockets.json: %s exceeds max_sockets" % k)
    for i, t in enumerate(rtiers):
        so = t.get("sockets")
        if not (isinstance(so, list) and len(so) == 2 and all(isinstance(x, int) for x in so)
                and 0 <= so[0] <= so[1] <= mx):
            errs.append("rarity %s: sockets must be [min, max] ints within 0..max_sockets (%d)"
                        % (t.get("id", i), mx))
    bi = _baseitems_2da()
    bases_json = {b["base"] for lst in data["bases"]["categories"].values() for b in lst}
    for row, cat in s.get("extra_bases", {}).items():
        tag = "sockets.json extra_bases %s" % row
        if cat not in CATEGORIES:
            errs.append("%s: unknown category %r" % (tag, cat))
        if not row.isdigit() or int(row) in bases_json:
            errs.append("%s: must be a base row not already in bases.json" % tag)
            continue
        r = bi.get(int(row))
        if not r:
            errs.append("%s: no such row in hak_2da/baseitems.2da" % tag)
        elif not int(r.get("EquipableSlots", "0x0"), 16) & PLAYER_SLOTS or int(_num(r.get("Stacking"), 1)) > 1:
            errs.append("%s: not a wearable single-stack base" % tag)
    for row, why in s.get("ignored_bases", {}).items():
        if not row.isdigit() or not why:
            errs.append("sockets.json ignored_bases %s: a base row with a reason" % row)
    for key in ("overrides", "exclude"):
        for rr, val in s.get(key, {}).items():
            tag = "sockets.json %s %s" % (key, rr)
            if not (UNPACKED / (rr + ".uti.json")).exists():
                errs.append("%s: no unpacked/%s.uti.json" % (tag, rr))
            if key == "overrides" and (not isinstance(val, int) or not 0 <= val <= mx):
                errs.append("%s: count must be an int 0..max_sockets" % tag)
            if key == "exclude" and not (isinstance(val, str) and val.strip()):
                errs.append("%s: give a reason" % tag)
    cats = socket_base_categories(data)
    ign = {int(r) for r in s.get("ignored_bases", {}) if r.isdigit()}
    untriaged = {}
    for p in sorted(UNPACKED.glob("*.uti.json")):
        u = json.loads(p.read_text())
        row = gff(u, "BaseItem")
        if row in cats or row in ign:
            continue
        r = bi.get(row)
        if not r:
            continue
        if int(r.get("EquipableSlots", "0x0"), 16) & PLAYER_SLOTS and int(_num(r.get("Stacking"), 1)) == 1:
            untriaged.setdefault(row, p.name[:-len(".uti.json")])
    for row, ex in sorted(untriaged.items()):
        errs.append("base item %d (%s, e.g. %s) is wearable but in neither bases.json, sockets.json "
                    "extra_bases nor ignored_bases - decide whether it takes sockets"
                    % (row, bi[row].get("label"), ex))

    # -- gems.json
    tiers = g.get("tiers", [])
    if len(tiers) != len(rtiers):
        errs.append("gems.json: tiers must match rarity.json (%d)" % len(rtiers))
    for i, t in enumerate(tiers):
        w = t.get("word", "")
        if not w or '"' in w or "\\" in w or not w.isascii():
            errs.append("gems.json tier %d: word must be plain ASCII" % i)
        if not isinstance(t.get("value"), int) or t["value"] < 1:
            errs.append("gems.json tier %d: value must be a positive int" % i)
    bands = g.get("level_bands", [])
    if not bands or bands[0].get("min_level") != 1:
        errs.append("gems.json: level_bands must start at min_level 1")
    for a, b in zip(bands, bands[1:]):
        if b["min_level"] <= a["min_level"]:
            errs.append("gems.json: level_bands must rise in min_level")
    for b in bands:
        if not (0 <= b.get("floor", -1) <= b.get("ceiling", -1) < len(rtiers)):
            errs.append("gems.json band %r: need 0 <= floor <= ceiling < %d" % (b, len(rtiers)))
    if not 0 <= g.get("boss_floor", 0) < len(rtiers):
        errs.append("gems.json: boss_floor out of range")
    seen = set()
    for fam in g["families"]:
        fid = fam.get("id", "")
        tag = "gems.json family %s" % fid
        if fid in seen:
            errs.append("%s: duplicate id" % tag)
        seen.add(fid)
        if not fid.isalpha() or fid != fid.lower() or len(gem_resref(fid, 0)) > 16:
            errs.append("%s: id must be lowercase letters, short enough for a 16-char resref" % tag)
        for k in ("stone", "effect"):
            v = fam.get(k, "")
            if not v or '"' in v or "\\" in v or not v.isascii():
                errs.append("%s: %s must be plain ASCII" % (tag, k))
        affs = fam.get("affixes", [])
        if not affs or any(a not in ab for a in affs):
            errs.append("%s: affixes must be loot/affixes.json ids" % tag)
            continue
        if any(ab[a]["role"] != "upside" for a in affs):
            errs.append("%s: a gem only raises upsides" % tag)
        ctabs = {costs["itempropdef"].get(str(ab[a]["type"]), {}).get("cost_table") for a in affs}
        if len(ctabs) != 1 or None in ctabs:
            errs.append("%s: its affixes must share one cost table" % tag)
            continue
        ct = ctabs.pop()
        types = {ab[a]["type"] for a in affs}
        lad = fam.get("ladder", [])
        if not lad or len(set(lad)) != len(lad):
            errs.append("%s: ladder must be non-empty with no repeated row" % tag)
            continue
        rows = costs["cost_tables"].get(ct, {})
        for r in lad:
            if str(r) not in rows:
                errs.append("%s: ladder row %r is not a row of %s" % (tag, r, ct))
        if types == {16}:
            mxs = [dmgmax.get(r, 0) for r in lad]
            if any(b <= a for a, b in zip(mxs, mxs[1:])):
                errs.append("%s: damage ladder must rise in maximum damage" % tag)
            cap = dmgpow.get(GEM_CAP_DAMAGE_ROW, 22)
            if any(dmgpow.get(r, 99) > cap or dmgmax.get(r, 99) > 20 for r in lad):
                errs.append("%s: damage ladder goes past the 2d10 socket cap" % tag)
        else:
            if lad != sorted(lad):
                errs.append("%s: ladder must rise" % tag)
            if types & set(HIT_TYPES) and max(lad) > GEM_CAP_HIT:
                errs.append("%s: ladder goes past the +%d socket cap" % (tag, GEM_CAP_HIT))
        st = fam.get("steps", [])
        if (len(st) != len(rtiers) or any(not isinstance(x, int) or x < 1 for x in st)
                or st != sorted(st) or (st and max(st) > len(lad))):
            errs.append("%s: steps must be %d non-decreasing ints 1..len(ladder)" % (tag, len(rtiers)))
        if not isinstance(fam.get("weight"), int) or fam["weight"] < 0:
            errs.append("%s: weight must be a non-negative int" % tag)
        m = fam.get("model")
        if not isinstance(m, int) or not 1 <= m <= 255:
            errs.append("%s: model must be a miscsmall ModelPart1 1..255 (pick it from the icon sheet)" % tag)
        if not any(gem_fits(data, fam, c) for c in CATEGORIES):
            errs.append("%s: fits no item category" % tag)
    if not any(f.get("weight", 0) > 0 for f in g["families"]):
        errs.append("gems.json: no family has a weight")
    # Blueprint freshness is checked by gen-loot-tables.py / the gate, like the
    # container wrappers (gem_blueprint_problems), so --apply can fix it.
    return errs
