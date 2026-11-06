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
                        ("area_levels", {"areas": {}}), ("_items", {"items": {}})):
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


def roll(data, level, floor=0, profile="lab", rng=None, model=None):
    """One rolled item as a dict (see keys at the end).  Mirrors Loot_Roll."""
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

    cats = [c for c in CATEGORIES if prof["categories"].get(c, 0) > 0]
    cat = weighted(rng, cats, lambda c: prof["categories"][c])
    bases = data["bases"]["categories"][cat]
    base = weighted(rng, bases, lambda b: b["weight"] if not allowed or b["base"] in allowed else 0)

    affixes = data["affixes"]["affixes"]
    lo_n, hi_n = tier["affixes"]
    n_up = lo_n + rng.randrange(hi_n - lo_n + 1)
    chosen = []          # [affix_index, ladder_index]
    used = set()

    has_down = False
    if rng.randrange(1000) < tier.get("downside_chance", 0):
        pool = [i for i, a in enumerate(affixes)
                if eligible(a, cat, level, "downside", used)]
        i = weighted(rng, pool, lambda k: affixes[k]["weight"])
        if i is not None:
            lo, hi = affix_window(affixes[i], level)
            chosen.append([i, lo + rng.randrange(hi - lo + 1)])
            used.add(affixes[i]["group"])
            has_down = True
            n_up += 1

    bias = tier.get("roll_bias", 0)
    for _ in range(n_up):
        pool = [i for i, a in enumerate(affixes)
                if eligible(a, cat, level, "upside", used)]
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

    value = model.item_value(base["base"], props())
    steps = 0
    while value > budget and steps < 64:
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
        value = model.item_value(base["base"], props())

    unid = rng.randrange(1000) < tier.get("unidentified_chance", 0)
    return {"named": None, "rarity": rar, "level": level, "category": cat,
            "base": base["base"], "base_name": base["name"],
            "affixes": [(affixes[i]["id"], affixes[i]["ladder"][k])
                        for i, k in chosen],
            "value": value, "budget": budget, "downside": has_down,
            "unidentified": unid,
            "name": item_name(base["name"], [affixes[i] for i, _ in chosen])}


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
            "downside": False}


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
                    "gold_pct": 0, "gem_chance": 0, "consumables": [0, 0]}


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
    out = {"gear": [], "gold": 0, "gems": [], "consumables": []}
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


def creature_drop(data, cls, cr, level, rng=None, model=None):
    """What one kill of a ``cls`` creature leaves on the corpse (a list of
    roll() dicts, empty when the drop chance misses).  Mirrors loot_ondeath."""
    rng = rng or random.Random()
    cfg = creatures_cfg(data)["classes"][cls]
    if rng.randrange(1000) >= int(cfg["chance"]):
        return []
    prof = data["sources"]["profiles"][cfg["profile"]]
    floor = int(prof_get(prof, "rarity_floor"))
    out = [roll(data, level, floor, cfg["profile"], rng, model)
           for _ in range(creature_rolls(data, cls, cr))]
    if rng.randrange(1000) < int(cfg.get("named_chance", 0)):
        n = give_named(data, level, len(data["rarity"]["tiers"]) - 1, prof.get("bases"), rng)
        if n:
            out.append(n)
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
        for k in ("chance", "named_chance"):
            v = cfg.get(k, 0)
            if not isinstance(v, int) or not 0 <= v <= 1000:
                errs.append("%s: %s must be an int 0..1000 (per mille)" % (tag, k))
        v = cfg.get("extra_roll_cr", 0)
        if not isinstance(v, int) or v < 0:
            errs.append("%s: extra_roll_cr must be a non-negative int" % tag)
        if name != "boss" and (cfg.get("named_chance") or cfg.get("extra_roll_cr")):
            errs.append("%s: named_chance and extra_roll_cr are boss-only" % tag)
        extra = set(cfg) - {"chance", "profile", "named_chance", "extra_roll_cr"}
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
        for k in ("rolls", "gear_chance", "gold_pct", "gem_chance"):
            v = prof_get(p, k)
            if not isinstance(v, int) or v < 0 or (k in ("gear_chance", "gem_chance") and v > 1000):
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
