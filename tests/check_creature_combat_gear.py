#!/usr/bin/env python3
"""Creature combat-start gear check (build-time smoke test).

WHY THIS EXISTS
    The wiki, the CR and whoever built a creature all read its EQUIPPED gear.
    The creature does not always fight with it. The stock AI (nw_c2_* /
    x2_def_* -> nw_i0_generic -> WrapperActionAttack) calls
    x0_i0_equip.nss bkEquipAppropriateWeapons at every attack, and its melee
    branch, bkEquipMelee, re-arms the creature out of its INVENTORY:

      1. Already holding a single-handed weapon in both hands -> nothing.
      2. Inventory holds a single-handed weapon AND a shield, and the creature
         has Shield Proficiency (feat 32), and its right hand is not a shield
         -> the FIRST inventory single-hander goes to the right hand and the
         (last) inventory shield to the left.
      3. Else two or more inventory single-handers and Ambidexterity (1) +
         Two-Weapon Fighting (41) -> the second goes right, the first left.
      4. Else any inventory single-hander -> it replaces the right hand (the
         second one found if there are two, else the first) -- even when the
         creature is already holding a better weapon.
      5. Else ActionEquipMostDamagingMelee (engine; not modelled, not flagged).

    "Single-handed" and "shield" are x0_i0_match.nss MatchSingleHandedWeapon /
    MatchShield: fixed lists of stock base items, so a CEP or custom base item
    is never picked by this routine.

    The Balrog of Moria was case 2 (roadmap wiki-ac-calc-off-balorg-of-moria-
    example, 017d7fe253d): Shield of the Fleet Elf in his pack plus feat 32, so
    he fought with ~10 more AC than the wiki showed. This gate finds every
    creature the same routine re-arms.

WHAT IT DOES NOT FLAG
    The roadmap item also asked for "gear the AI unequips for lack of
    proficiency". The stock routine above never unequips anything for that
    reason -- its only proficiency test is feat 32 -- so there is nothing to
    model. A creature holding a ranged weapon keeps it until an enemy closes to
    melee range and only then draws an inventory blade -- the intended archer
    behaviour, so it is not flagged. The six creatures on Jasperre's AI (any j_ai_* event script) run a
    different routine and are skipped, as are creatures with no combat-round
    script at all (they never fight through the AI).

    Inventory order is the blueprint's ItemList order, which is how the engine
    builds the inventory; that decides "first" and "second" above.

BURN-DOWN
    tests/known_combat_gear.json records what the routine does to each creature
    as of when the gate landed, with a reason. A creature NOT in that file, or
    one whose re-arm has changed, fails the repack. An entry that no longer
    re-arms is a warning: drop it from the file (or re-run with --write-known).
    Fix a creature either by moving the inventory item into the slot it will
    end up in anyway (the wiki then tells the truth), or by removing the feat /
    item that triggers the swap.

    python3 tests/check_creature_combat_gear.py               # the gate
    python3 tests/check_creature_combat_gear.py --report      # every re-arm
    python3 tests/check_creature_combat_gear.py --write-known # rebaseline

Base items of stock (non-module) items come from tests/stock_item_bases.json
(bin/gen-stock-item-bases.py), so the gate never needs a NWN install.
Exits 0 when nothing new re-arms, 1 otherwise.
"""

import argparse
import glob
import json
import os
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
UNPACKED = os.path.join(ROOT, "unpacked")
KNOWN = os.path.join(ROOT, "tests", "known_combat_gear.json")
STOCK = os.path.join(ROOT, "tests", "stock_item_bases.json")

# x0_i0_match.nss MatchSingleHandedWeapon: shortsword 0, longsword 1,
# battleaxe 2, bastardsword 3, light flail 4, warhammer 5, light mace 9,
# dagger 22, club 28, heavy flail 35, light hammer 37, handaxe 38, kama 40,
# katana 41, kukri 42, morningstar 47, rapier 51, scimitar 53, sickle 60,
# dwarven waraxe 108, whip 111.
SINGLE_HANDED = frozenset({0, 1, 2, 3, 4, 5, 9, 22, 28, 35, 37, 38, 40, 41, 42,
                           47, 51, 53, 60, 108, 111})
# MatchShield: small 14, large 56, tower 57.
SHIELDS = frozenset({14, 56, 57})
# GetWeaponRanged: light/heavy crossbow 6/7, longbow 8, shortbow 11, dart 31,
# shuriken 59, sling 61, throwing axe 63.
RANGED = frozenset({6, 7, 8, 11, 31, 59, 61, 63})

FEAT_AMBIDEXTERITY = 1
FEAT_TWO_WEAPON_FIGHTING = 41
FEAT_SHIELD_PROFICIENCY = 32
# ITEM_PROPERTY_BONUS_FEAT (12) subtype = iprp_feats row -> feat (FeatIndex).
IP_BONUS_FEAT = 12
IPRP_FEAT = {1: FEAT_AMBIDEXTERITY, 17: FEAT_TWO_WEAPON_FIGHTING,
             35: FEAT_SHIELD_PROFICIENCY}

SLOT_RIGHT, SLOT_LEFT = 16, 32


def fld(s, k):
    v = s.get(k) if isinstance(s, dict) else None
    return v.get("value") if isinstance(v, dict) else None


def loc(s, k):
    v = fld(s, k)
    if isinstance(v, dict):
        return v.get("0") or (f"<tlk {v['id']}>" if "id" in v else "")
    return v or ""


class Items:
    def __init__(self):
        self.cache = {}
        try:
            self.stock = json.load(open(STOCK, encoding="utf-8"))["bases"]
        except (OSError, ValueError, KeyError):
            self.stock = {}

    def get(self, resref):
        if resref not in self.cache:
            p = os.path.join(UNPACKED, f"{resref}.uti.json")
            self.cache[resref] = (json.load(open(p, encoding="utf-8"))
                                  if os.path.exists(p) else None)
        return self.cache[resref]

    def base(self, resref):
        u = self.get(resref)
        if u is not None:
            return fld(u, "BaseItem")
        return self.stock.get(resref)

    def name(self, resref):
        u = self.get(resref)
        return (loc(u, "LocalizedName") or resref) if u else resref

    def bonus_feats(self, resref):
        u = self.get(resref)
        out = set()
        for p in (fld(u, "PropertiesList") or []) if u else []:
            if fld(p, "PropertyName") == IP_BONUS_FEAT:
                f = IPRP_FEAT.get(fld(p, "Subtype"))
                if f is not None:
                    out.add(f)
        return out


def uses_stock_ai(c):
    scripts = [fld(c, k) or "" for k in c if k.startswith("Script")]
    if any(s.lower().startswith("j_ai") for s in scripts):
        return False
    return bool(fld(c, "ScriptEndRound"))


def rearm(c, items):
    """What bkEquipMelee does to this blueprint at its first attack.

    Returns None when nothing changes, else a dict describing the swap.
    """
    equipped = {}
    feats = {fld(f, "Feat") for f in (fld(c, "FeatList") or [])}
    for e in fld(c, "Equip_ItemList") or []:
        r = fld(e, "EquippedRes")
        equipped[e.get("__struct_id")] = r
        feats |= items.bonus_feats(r)
    inv = [fld(e, "InventoryRes") for e in (fld(c, "ItemList") or [])]

    right, left = equipped.get(SLOT_RIGHT), equipped.get(SLOT_LEFT)
    single = lambda r: r is not None and items.base(r) in SINGLE_HANDED  # noqa: E731
    shield = lambda r: r is not None and items.base(r) in SHIELDS        # noqa: E731

    if single(right) and single(left):
        return None
    # A ranged weapon in hand is kept until an enemy closes to melee range;
    # switching to an inventory blade then is the intended archer behaviour.
    if right is not None and items.base(right) in RANGED:
        return None
    singles = [r for r in inv if single(r)]
    shields = [r for r in inv if shield(r)]
    first = singles[0] if singles else None
    second = singles[1] if len(singles) > 1 else None

    if first and shields and FEAT_SHIELD_PROFICIENCY in feats and not shield(right):
        rule, new_r, new_l = "shield", first, shields[-1]
    elif second and {FEAT_AMBIDEXTERITY, FEAT_TWO_WEAPON_FIGHTING} <= feats:
        rule, new_r, new_l = "dual", second, first
    elif first:
        rule, new_r, new_l = "right-hand", second or first, left
    else:
        return None
    if (new_r, new_l) == (right, left):
        return None
    return {"rule": rule, "from": [right, left], "to": [new_r, new_l]}


def signature(swap):
    return f"{swap['rule']}: {swap['from']} -> {swap['to']}"


def describe(swap, items):
    nm = lambda r: items.name(r) if r else "(empty)"  # noqa: E731
    (fr, fl), (tr, tl) = swap["from"], swap["to"]
    parts = []
    if fr != tr:
        parts.append(f"right hand {nm(fr)} -> {nm(tr)}")
    if fl != tl:
        parts.append(f"left hand {nm(fl)} -> {nm(tl)}")
    why = {"shield": "inventory shield + single-hander, has Shield Proficiency",
           "dual": "two inventory single-handers, has Ambidexterity + TWF",
           "right-hand": "inventory single-hander replaces the right hand"}[swap["rule"]]
    return "; ".join(parts) + f" ({why})"


def scan():
    items = Items()
    found = {}
    for path in sorted(glob.glob(os.path.join(UNPACKED, "*.utc.json"))):
        c = json.load(open(path, encoding="utf-8"))
        if not uses_stock_ai(c):
            continue
        swap = rearm(c, items)
        if swap:
            resref = os.path.basename(path)[:-len(".utc.json")]
            name = (loc(c, "FirstName") + " " + loc(c, "LastName")).strip()
            found[resref] = {"name": name, "swap": signature(swap),
                             "what": describe(swap, items)}
    return found


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--report", action="store_true", help="list every re-arm")
    ap.add_argument("--write-known", action="store_true",
                    help="rewrite tests/known_combat_gear.json from the current tree "
                         "(keeps existing reasons)")
    args = ap.parse_args()

    found = scan()
    try:
        known = json.load(open(KNOWN, encoding="utf-8"))
    except (OSError, ValueError):
        known = {"known": {}}
    kmap = known.get("known", {})

    if args.write_known:
        out = {}
        for r, f in sorted(found.items()):
            old = kmap.get(r, {})
            out[r] = {"name": f["name"], "swap": f["swap"], "what": f["what"],
                      "reason": old.get("reason") or
                      "pre-existing when the gate landed (2026-11-19); untriaged"}
        known["known"] = out
        known.setdefault("_comment", [
            "Creatures the stock AI re-arms from inventory at combat start",
            "(x0_i0_equip bkEquipMelee). Burn-down list for",
            "tests/check_creature_combat_gear.py: every entry is a creature",
            "that does not fight with the gear its blueprint (and the wiki) shows.",
            "Fix one, then delete its entry. Never add a new one by hand to get",
            "past the gate without a reason someone can check."])
        with open(KNOWN, "w", encoding="utf-8") as fh:
            fh.write(json.dumps(known, indent=1, ensure_ascii=False) + "\n")
        print(f"[combat-gear] wrote {len(out)} known re-arm(s) to "
              f"{os.path.relpath(KNOWN, ROOT)}")
        return 0

    if args.report:
        for r, f in sorted(found.items()):
            print(f"{r:18} {f['name'][:28]:28} {f['what']}")

    new = {r: f for r, f in found.items()
           if r not in kmap or kmap[r].get("swap") != f["swap"]}
    gone = sorted(r for r in kmap if r not in found)
    for r in gone:
        print(f"[combat-gear] note: {r} no longer re-arms at combat start; "
              f"delete it from {os.path.relpath(KNOWN, ROOT)}")
    if new:
        print(f"[combat-gear] FAIL: {len(new)} creature(s) fight with different gear "
              "than their blueprint equips (x0_i0_equip bkEquipMelee):")
        for r, f in sorted(new.items()):
            was = kmap.get(r, {}).get("swap")
            print(f"  {r} ({f['name']}): {f['what']}" +
                  (f"\n      changed from: {was}" if was else ""))
        print("  Put the item in the slot the AI moves it to, or remove what triggers "
              "the swap. See this script's header.")
        return 1
    print(f"[combat-gear] OK: no new combat-start re-arms "
          f"({len(found)} known, burn-down in {os.path.relpath(KNOWN, ROOT)}).")
    return 0


if __name__ == "__main__":
    sys.exit(main())
