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
    """Every loot/*.json file, keyed by stem.  ``costs`` is the 2DA snapshot."""
    d = {}
    for stem in ("rarity", "levels", "bases", "affixes", "named", "sources"):
        d[stem] = _load(stem + ".json")
    d["costs"] = _load("_costs.json")
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

    # Named pool: a Legendary roll may award a curated existing item instead.
    if rng.randrange(1000) < tier.get("named_chance", 0):
        pool = [n for n in data["named"]["items"]
                if n["min_level"] <= level <= n["max_level"]]
        n = weighted(rng, pool, lambda x: x.get("weight", 1))
        if n:
            return {"named": n["resref"], "rarity": rar, "level": level,
                    "affixes": [], "value": None, "unidentified": False,
                    "downside": False}

    prof = data["sources"]["profiles"][profile]
    cats = [c for c in CATEGORIES if prof["categories"].get(c, 0) > 0]
    cat = weighted(rng, cats, lambda c: prof["categories"][c])
    bases = data["bases"]["categories"][cat]
    base = weighted(rng, bases, lambda b: b["weight"])

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


def item_name(base_name, chosen_affixes):
    ups = [a for a in chosen_affixes if a["role"] == "upside"]
    name = base_name
    if ups:
        name = ups[0]["prefix"] + " " + name
    if len(ups) > 1:
        name = name + " of " + ups[1]["suffix"]
    return name


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
    if "lab" not in data["sources"]["profiles"]:
        errs.append("sources.json: the 'lab' profile (Loot Lab) is required")

    # -- sanity ceiling against the module's own obtainable gear
    if item_index is not None:
        top = max((int(float(i.get("cost_gp") or 0)) for i in item_index
                   if i.get("accessible")), default=0)
        b = rarity_budget(tiers[-1], MAX_LEVEL, True)
        if top and b > top:
            errs.append("top-tier budget at level %d (%d gp) exceeds the most valuable "
                        "obtainable item (%d gp)" % (MAX_LEVEL, b, top))
    return errs
