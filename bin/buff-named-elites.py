#!/usr/bin/env python3
"""Make the creatures NAMED "Elite" strong enough to BE elite (Loot Overhaul Phase 4).

Phase 4's elite rule is purely mechanical: a creature is elite when its CR's
loot level is at least its area's loot level (median hostile CR) + elite_margin.
Several creatures are called "Elite" but fall short of it.  The admin's call
(2026-11-06) was to make them genuinely stronger - never to label them elite by
name - and let the stored CR, recomputed with the toolset's own formula
(nwn_manager bin/nwn-cr), carry them over the line.

Each PACKAGES entry is a real stat and gear buff:

  hp_add / ability_add / natural_ac_add / saves_add
      base HitPoints (MaxHitPoints and CurrentHitPoints follow, including the
      Con-modifier change), all six ability scores, NaturalAC, and the innate
      fort/ref/will bonuses.
  weapon / hide
      a NEW copy of an equipped item (the originals are shared with other
      creatures), with properties replaced or added.  Its Cost is recomputed by
      loot_model.CostModel, which reproduces the toolset's item price, so the
      CR formula's item term stays honest.  The hide is a creature-slot item:
      the CR formula ignores it, so regeneration there is power without CR.

After the stat change the stored ChallengeRating is resynced with
``nwn-cr --resync`` (blueprint, placed instances, encounter CR caches).

LOCKSTEP: blueprint and every placed instance change together, the same rule
as bin/bump-legendary-npcs.py (tests/check_divergent_creatures.py fails the
repack otherwise; se_respawn rebuilds a dead placed creature from the blueprint).
Encounter-spawned creatures read the blueprint.  IDEMPOTENT: each struct gets
an ELITE_BUFF_V VarTable marker and is skipped once it has one.

    python3 bin/buff-named-elites.py            # dry run
    python3 bin/buff-named-elites.py --apply    # write, resync CR, file the new items
"""

import argparse
import copy
import json
import subprocess
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
UNPACKED = ROOT / "unpacked"
sys.path.insert(0, str(ROOT / "bin"))
import loot_model as lm  # noqa: E402

NWN_CR = ROOT.parent / "nwn_manager" / "bin" / "nwn-cr"
MARKER = "ELITE_BUFF_V"
MARKER_VERSION = 1
ABILITIES = ("Str", "Dex", "Con", "Int", "Wis", "Cha")

# Item property encodings (itempropdef rows): 6 enhancement (cost table 2),
# 16 damage bonus (subtype iprp_damagetype, cost table 4 iprp_damagecost),
# 51 regeneration (cost table 2).
PACKAGES = {
    "gntfrost003": {
        "why": "Carrok Elite Guard: CR 16 in Carrok (area loot level 12) needs CR 23 to be elite",
        "hp_add": 115,            # base HitPoints 115 -> 230
        "ability_add": 6,
        "natural_ac_add": 10,
        "saves_add": 4,
        "weapon": {"slot": 16, "from": "wblmfh012", "to": "carrokeliteflai",
                   "name": "Carrok Elite Guard's Flail",
                   # cold 1d10 -> 2d6, enhancement +3 -> +4
                   "set": [(16, 7, 4, 10), (6, 0, 2, 4)]},
        "hide": {"slot": 131072, "from": "it_creitem002", "to": "carrokelitehide",
                 "name": "Carrok Elite Guard Properties",
                 "set": [(51, 0, 2, 3)]},     # + regeneration 3
    },
}


def gv(node, default=None):
    return node["value"] if isinstance(node, dict) and "value" in node else default


def fld(s, k, default=None):
    return gv(s.get(k), default) if isinstance(s, dict) else default


def dump(obj):
    return json.dumps(obj, indent=2, ensure_ascii=False) + "\n"


def has_marker(s):
    return any(fld(r, "Name") == MARKER and fld(r, "Value") for r in fld(s, "VarTable", []) or [])


def set_marker(s):
    vt = s.get("VarTable")
    rows = vt.get("value") if isinstance(vt, dict) else None
    if not isinstance(rows, list):
        rows = []
        s["VarTable"] = {"type": "list", "value": rows}
    rows.append({"__struct_id": 0,
                 "Name": {"type": "cexostring", "value": MARKER},
                 "Type": {"type": "dword", "value": 1},
                 "Value": {"type": "int", "value": MARKER_VERSION}})


def bump(s, key, add):
    s[key]["value"] = int(s[key]["value"]) + add


def make_item(spec, cm, apply):
    """Copy spec['from'] to spec['to'] with properties replaced/added; returns its Cost."""
    src = json.loads((UNPACKED / f"{spec['from']}.uti.json").read_text(encoding="utf-8"))
    d = copy.deepcopy(src)
    d["TemplateResRef"]["value"] = spec["to"]
    d["Tag"]["value"] = spec["to"]
    d["LocalizedName"]["value"] = {"0": spec["name"]}
    props = d["PropertiesList"]["value"]
    for ptype, sub, table, cost in spec["set"]:
        hit = [p for p in props if fld(p, "PropertyName") == ptype and fld(p, "Subtype") == sub]
        if hit:
            hit[0]["CostValue"]["value"] = cost
        else:
            props.append({"__struct_id": 0,
                          "ChanceAppear": {"type": "byte", "value": 100},
                          "CostTable": {"type": "byte", "value": table},
                          "CostValue": {"type": "word", "value": cost},
                          "Param1": {"type": "byte", "value": 255},
                          "Param1Value": {"type": "byte", "value": 255},
                          "PropertyName": {"type": "word", "value": ptype},
                          "Subtype": {"type": "word", "value": sub}})
    d["Cost"]["value"] = cm.item_value(fld(d, "BaseItem"), [
        (fld(p, "PropertyName"), fld(p, "Subtype"), fld(p, "CostValue")) for p in props])
    out = UNPACKED / f"{spec['to']}.uti.json"
    text = dump(d)
    changed = not out.exists() or out.read_text(encoding="utf-8") != text
    print(f"  item {spec['to']} ({spec['name']}) from {spec['from']}: Cost "
          f"{fld(src, 'Cost')} -> {fld(d, 'Cost')}{'' if changed else ' (unchanged)'}")
    if apply and changed:
        out.write_text(text, encoding="utf-8")


def buff_struct(s, pkg, where):
    """Mutate one creature struct (blueprint or placed instance). False if already done."""
    if has_marker(s):
        print(f"  {where}: already buffed ({MARKER}), skipped")
        return False
    con_mod_before = (int(fld(s, "Con", 10)) - 10) // 2
    for a in ABILITIES:
        bump(s, a, pkg.get("ability_add", 0))
    con_mod_after = (int(fld(s, "Con", 10)) - 10) // 2
    hd = sum(int(fld(c, "ClassLevel", 0)) for c in fld(s, "ClassList", []))
    hp = pkg.get("hp_add", 0)
    bump(s, "HitPoints", hp)
    bump(s, "MaxHitPoints", hp + (con_mod_after - con_mod_before) * hd)
    bump(s, "CurrentHitPoints", hp)
    bump(s, "NaturalAC", pkg.get("natural_ac_add", 0))
    for k in ("fortbonus", "refbonus", "willbonus"):
        bump(s, k, pkg.get("saves_add", 0))
    for key in ("weapon", "hide"):
        spec = pkg.get(key)
        if not spec:
            continue
        for e in fld(s, "Equip_ItemList", []):
            if e.get("__struct_id") != spec["slot"]:
                continue
            if "EquippedRes" in e:
                e["EquippedRes"]["value"] = spec["to"]
            else:   # an instance embeds the whole item: swap in the new item struct
                new = json.loads((UNPACKED / f"{spec['to']}.uti.json").read_text(encoding="utf-8"))
                keep = {k: e[k] for k in ("__struct_id", "Dropable") if k in e}
                e.clear()
                e.update({k: v for k, v in new.items() if k != "__data_type"})
                e.update(keep)
    set_marker(s)
    print(f"  {where}: +{hp} base HP, +{pkg.get('ability_add', 0)} abilities, "
          f"+{pkg.get('natural_ac_add', 0)} natural AC, +{pkg.get('saves_add', 0)} saves")
    return True


def main():
    ap = argparse.ArgumentParser(description=__doc__,
                                 formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--apply", action="store_true")
    a = ap.parse_args()
    cm = lm.CostModel(lm.load_data()["costs"])
    touched = []
    for rr, pkg in PACKAGES.items():
        print(f"{rr}: {pkg['why']}")
        for key in ("weapon", "hide"):
            if pkg.get(key):
                make_item(pkg[key], cm, a.apply)
        bp = UNPACKED / f"{rr}.utc.json"
        d = json.loads(bp.read_text(encoding="utf-8"))
        if buff_struct(d, pkg, f"{rr}.utc"):
            touched.append(rr)
            if a.apply:
                bp.write_text(dump(d), encoding="utf-8")
        for git in sorted(UNPACKED.glob("*.git.json")):
            g = json.loads(git.read_text(encoding="utf-8"))
            hit = False
            for c in fld(g, "Creature List", []) or []:
                if (fld(c, "TemplateResRef", "") or "").lower() == rr:
                    hit |= buff_struct(c, pkg, f"{git.name} placed {rr}")
            if hit and a.apply:
                git.write_text(dump(g), encoding="utf-8")
    if not a.apply:
        print("dry run - re-run with --apply")
        return
    if touched:
        subprocess.run([sys.executable, str(NWN_CR), "--project", str(ROOT),
                        "--resync", ",".join(touched), "--apply"], check=True)
    subprocess.run([sys.executable, str(ROOT / "bin" / "file-palette-orphans.py"), "--apply"],
                   check=True)


if __name__ == "__main__":
    main()
