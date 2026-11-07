#!/usr/bin/env python3
"""gen-loot-tables.py - loot/*.json -> unpacked/loot_data_inc.nss.

Season 3 rolled loot (roadmap ``lo-loot-core``).  The tables are compiled into
the module rather than kept in a campaign DB, so the dev and live realms can
never drift apart.  The generated include is committed and never hand-edited;
``tests/check_loot_tables.py`` fails the repack when it is stale or when the
JSON breaks a rule (see bin/loot_model.py ``validate``).

    python3 bin/gen-loot-tables.py                  # dry run: validate + say if stale
    python3 bin/gen-loot-tables.py --apply          # write unpacked/loot_data_inc.nss and the
                                                    #   container wrapper scripts (sources.json
                                                    #   "scripts": chest_*, nw_o2_*, x0_o2_*, x2_02_*),
                                                    #   unpacked/socket_data_inc.nss and the
                                                    #   sgem_* gem blueprints (loot/gems.json),
                                                    #   and the wiki's loot tables in
                                                    #   docs.manual/Customizations/Loot.html
                                                    #   (bin/gen-loot-doc.py; then run
                                                    #   gen-customizations-hub.py)
    python3 bin/gen-loot-tables.py --refresh-costs  # re-snapshot loot/_costs.json
                                                    #   from the 2DAs (stock + CEP
                                                    #   haks + hak_2da/), needs NWN
    python3 bin/gen-loot-tables.py --harvest-donors # refill bases.json appearance
                                                    #   donors from unpacked/*.uti

After any change to loot/*.json: --apply, then commit the JSON and the include
together.  ``loot_data_inc`` is an include; its only consumer is loot_inc
(itself an include), so a plain repack does rebuild the scripts that use it
only when THEIR source changed -- after editing loot data, use
repack-homers-lotr-clean (CLAUDE.md, "Editing a .nss include").
"""

from __future__ import annotations

import argparse
import collections
import importlib.util
import json
import os
import shutil
import subprocess
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
import loot_model as lm  # noqa: E402

ROOT = lm.ROOT

_dspec = importlib.util.spec_from_file_location("gen_loot_doc", ROOT / "bin" / "gen-loot-doc.py")
lootdoc = importlib.util.module_from_spec(_dspec)
_dspec.loader.exec_module(lootdoc)


# --------------------------------------------------------------------------
# --refresh-costs
# --------------------------------------------------------------------------

def _server_env():
    env = {}
    p = ROOT / "server.env"
    for ln in p.read_text().splitlines():
        ln = ln.strip()
        if ln and not ln.startswith("#") and "=" in ln:
            k, v = ln.split("=", 1)
            env[k.strip()] = v.strip().strip('"')
    return env


def _tool(name):
    cand = os.path.expanduser("~/.nimble/bin/" + name)
    if os.path.exists(cand):
        return cand
    if shutil.which(name):
        return name
    sys.exit("%s not found (neverwinter.nim tools)" % name)


def _resman_reader():
    """Return read(name) -> 2DA text with the module's hak stack applied.

    hak_2da/ (the source of lotr_rules/lotr_iprp) wins over everything, the
    module's hak list wins over stock in NWN order (first hak = highest)."""
    home = _server_env().get("NWN_HOME_DIR", "").replace("$HOME", os.path.expanduser("~"))
    ifo = json.loads((lm.UNPACKED / "module.ifo.json").read_text())
    haks = [h["Mod_Hak"]["value"] for h in ifo["Mod_HakList"]["value"]]
    erfs = [os.path.join(home, "hak", h + ".hak") for h in reversed(haks)]
    erfs = [e for e in erfs if os.path.exists(e)]
    tool = _tool("nwn_resman_cat")

    def read(name):
        local = ROOT / "hak_2da" / (name.lower() + ".2da")
        if local.exists():
            return local.read_text(encoding="latin-1")
        r = subprocess.run([tool, "--quiet", "--erfs", ",".join(erfs), name.lower() + ".2da"],
                           capture_output=True, text=True, encoding="latin-1")
        if r.returncode != 0:
            return None
        return r.stdout
    return read


FOCUS_FEAT_COLS = ("WeaponFocusFeat", "EpicWeaponFocusFeat", "WeaponSpecializationFeat",
                   "EpicWeaponSpecializationFeat", "WeaponImprovedCriticalFeat",
                   "EpicWeaponOverwhelmingCriticalFeat", "EpicWeaponDevastatingCriticalFeat",
                   "WeaponOfChoiceFeat")
REQ_FEAT_COLS = ("ReqFeat0", "ReqFeat1", "ReqFeat2", "ReqFeat3", "ReqFeat4")
# Cost-table columns that say what a row means (snapshotted as cost_labels).
LABEL_COLS = ("Label", "Value", "Amount", "NumDice", "Die")


def refresh_costs():
    read = _resman_reader()
    _, ipd = lm.read_2da_text(read("itempropdef"))
    _, ctab = lm.read_2da_text(read("iprp_costtable"))
    ct_name = {i: r["Name"].lower() for i, r in ctab.items() if r.get("Name", "****") != "****"}

    out = {"_doc": "GENERATED by bin/gen-loot-tables.py --refresh-costs from the 2DAs "
                   "(stock + the module's CEP haks + hak_2da/). Do not edit. The loot "
                   "gate and loot-sim read it so they need no NWN install.",
           "itempropdef": {}, "cost_tables": {}, "cost_labels": {}, "subtype_costs": {},
           "subtype_rows": {}, "baseitems": {}, "armor_cost": {}, "parts_chest": {}}
    for t in sorted(lm.SUPPORTED_IP):
        r = ipd[t]
        st = r.get("SubTypeResRef", "****")
        st = None if st == "****" else st.lower()
        cti = r.get("CostTableResRef", "****")
        ct = None
        if cti not in ("****", "0"):
            ct = ct_name.get(int(cti))
        out["itempropdef"][str(t)] = {"label": r.get("Label"), "cost": lm._num(r.get("Cost")),
                                      "subtype_table": st, "cost_table": ct}
        if ct and ct not in out["cost_tables"]:
            _, rows = lm.read_2da_text(read(ct))
            out["cost_tables"][ct] = {str(k): lm._num(v.get("Cost"), 0.0) for k, v in rows.items()
                                      if v.get("Label", v.get("Name")) not in ("Random",)
                                      and lm._num(v.get("Cost")) is not None}
            # What each row means in game, for bin/gen-loot-doc.py's wiki tables
            # (the cost column alone cannot say "1d6" or "-30%").
            out["cost_labels"][ct] = {
                str(k): {c: v[c] for c in LABEL_COLS if v.get(c) not in (None, "****")}
                for k, v in rows.items()
                if v.get("Label", v.get("Name")) not in ("Random",)
                and lm._num(v.get("Cost")) is not None}
        if st and st not in out["subtype_rows"]:
            _, rows = lm.read_2da_text(read(st))
            valid = {}
            for k, v in rows.items():
                lab = v.get("Label", v.get("label", v.get("Name", "****")))
                if lab and lab != "****":
                    valid[str(k)] = lm._num(v.get("Cost"))
            out["subtype_rows"][st] = sorted(valid, key=int)
            out["subtype_costs"][st] = {k: c for k, c in valid.items() if c is not None}

    _, bi = lm.read_2da_text(read("baseitems"))
    _, chest = lm.read_2da_text(read("parts_chest"))
    out["parts_chest"] = {str(k): int(lm._num(v.get("ACBONUS"), 0))
                          for k, v in chest.items() if lm._num(v.get("ACBONUS")) is not None}
    _, arm = lm.read_2da_text(read("armor"))
    out["armor_cost"] = {str(k): lm._num(v.get("COST"), 0) for k, v in arm.items()}
    for p in sorted(lm.UNPACKED.glob("forge_blank_*.uti.json")):
        row = int(p.name[len("forge_blank_"):-len(".uti.json")])
        r = bi.get(row)
        if not r:
            continue
        ent = {"label": r.get("label"), "base_cost": lm._num(r.get("BaseCost"), 0),
               "mult": lm._num(r.get("ItemMultiplier"), 1),
               "stacking": int(lm._num(r.get("Stacking"), 1)),
               "model_type": int(lm._num(r.get("ModelType"), 0)), "armor_ac": None,
               # Phase 6 wishlist Auto: the weapon-focus family feats of the base
               # (tier 1) and the proficiency feats any one of which lets a
               # character use it (tier 2; none = anyone).
               "focus_feats": [int(r[c]) for c in FOCUS_FEAT_COLS
                               if lm._num(r.get(c)) is not None],
               "req_feats": [int(r[c]) for c in REQ_FEAT_COLS
                             if lm._num(r.get(c)) is not None]}
        if row == 16:
            u = json.loads(p.read_text())
            ent["armor_ac"] = out["parts_chest"].get(str(lm.gff(u, "ArmorPart_Torso", 0)), 0)
        out["baseitems"][str(row)] = ent
    # Phase 6: class rows that cast spells (classes.2da SpellCaster) - the
    # wishlist's proficiency tier offers a magic staff only to a caster.
    _, cls = lm.read_2da_text(read("classes"))
    out["caster_classes"] = sorted(int(k) for k, v in cls.items()
                                   if lm._num(v.get("SpellCaster"), 0) == 1)
    path = lm.LOOT_DIR / "_costs.json"
    path.write_text(json.dumps(out, indent=1, sort_keys=True) + "\n")
    print("wrote %s (%d property types, %d cost tables, %d base items)"
          % (path.relative_to(ROOT), len(out["itempropdef"]), len(out["cost_tables"]),
             len(out["baseitems"])))


# --------------------------------------------------------------------------
# --harvest-donors
# --------------------------------------------------------------------------

DONOR_CAP = 16
ARMOR_DONOR_CAP = 27   # 3 per AC 0..8


def harvest_donors():
    data = lm.load_data()
    costs = data["costs"]
    seen = collections.defaultdict(collections.Counter)
    for p in sorted(lm.UNPACKED.glob("*.uti.json")):
        if p.name.startswith("forge_blank_"):
            continue
        u = json.loads(p.read_text())
        row = lm.gff(u, "BaseItem")
        bi = costs["baseitems"].get(str(row))
        if not bi:
            continue
        mt = bi["model_type"]
        if mt in (0, 1):
            t = (lm.gff(u, "ModelPart1", 0),)
        elif mt == 2:
            t = (lm.gff(u, "ModelPart1", 0), lm.gff(u, "ModelPart2", 0), lm.gff(u, "ModelPart3", 0))
        else:
            t = tuple(lm.gff(u, "ArmorPart_" + n, 0) for n in lm.ARMOR_PARTS)
        seen[row][t] += 1
    bases = json.loads((lm.LOOT_DIR / "bases.json").read_text())
    for cat, lst in bases["categories"].items():
        for b in lst:
            c = seen.get(b["base"], collections.Counter())
            ranked = sorted(c, key=lambda t: (-c[t], t))
            if costs["baseitems"][str(b["base"])]["model_type"] == 3:
                by_ac = collections.defaultdict(list)
                for t in ranked:
                    by_ac[costs["parts_chest"].get(str(t[lm.TORSO]), 0)].append(t)
                pick = []
                for ac in sorted(by_ac):
                    pick += by_ac[ac][:3]
                ranked = pick[:ARMOR_DONOR_CAP]
            else:
                ranked = ranked[:DONOR_CAP]
            b["donors"] = [list(t) for t in ranked]
            print("%-9s %-16s %d donors" % (cat, b["name"], len(b["donors"])))
    (lm.LOOT_DIR / "bases.json").write_text(_dump_bases(bases))


def _dump_bases(bases):
    """bases.json with one donor per line, so diffs stay readable."""
    s = json.dumps(bases, indent=2)
    import re
    return re.sub(r"\[\s+((?:-?\d+,\s+)*-?\d+)\s+\]",
                  lambda m: "[" + ", ".join(x.strip() for x in m.group(1).split(",")) + "]",
                  s) + "\n"


# --------------------------------------------------------------------------
# The include
# --------------------------------------------------------------------------

def _q(s):
    assert '"' not in s and "\\" not in s, s
    return '"' + s + '"'


def _interp_body(points, var="nLvl", indent="        "):
    """Emit integer piecewise-linear interpolation, matching interp_points()."""
    out = []
    x0, y0 = points[0]
    out.append("%sif (%s <= %d) return %d;" % (indent, var, x0, y0))
    for (xa, ya), (xb, yb) in zip(points, points[1:]):
        if ya == yb:
            out.append("%sif (%s <= %d) return %d;" % (indent, var, xb, ya))
        else:
            out.append("%sif (%s <= %d) return %d + (%d * (%s - %d)) / %d;"
                       % (indent, var, xb, ya, yb - ya, var, xa, xb - xa))
    out.append("%sreturn %d;" % (indent, points[-1][1]))
    return out


def _switch_fn(sig, cases, default, ret_fmt):
    """int/str switch(nI) {case k: return v;}."""
    lines = [sig, "{", "    switch (nI)", "    {"]
    for k, v in cases:
        lines.append("        case %d: return %s;" % (k, ret_fmt(v)))
    lines += ["    }", "    return %s;" % default, "}", ""]
    return lines


def nss_include(data=None):
    data = data or lm.load_data()
    tiers = data["rarity"]["tiers"]
    affixes = data["affixes"]["affixes"]
    named = data["named"]["items"]
    profiles = data["sources"]["profiles"]
    cats = list(lm.CATEGORIES)
    bases = data["bases"]["categories"]
    costs = data["costs"]
    L = []
    w = L.append
    w("// loot_data_inc.nss - GENERATED by bin/gen-loot-tables.py. Do not edit.")
    w("// Re-run: python3 bin/gen-loot-tables.py --apply   (source: loot/*.json)")
    w("// Read by loot_inc.nss. Every value here is validated by")
    w("// tests/check_loot_tables.py before a repack may proceed.")
    w("")
    w("const int LOOTD_RARITY_COUNT = %d;" % len(tiers))
    w("const int LOOTD_CAT_COUNT = %d;" % len(cats))
    w("const int LOOTD_AFFIX_COUNT = %d;" % len(affixes))
    w("const int LOOTD_NAMED_COUNT = %d;" % len(named))
    w("const int LOOTD_MAX_LEVEL = %d;" % lm.MAX_LEVEL)
    w("const int LOOTD_MAX_PROPS = %d;" % lm.FORGE_LEGAL_MAX_PROPS)
    w("")

    # -- rarity
    def tier_fn(name, key, typ="int", fmt=str, default="0"):
        L.extend(_switch_fn("%s LootD_Rarity%s(int nI)" % (typ, name),
                            [(i, t.get(key, 0)) for i, t in enumerate(tiers)], default, fmt))
    tier_fn("Name", "name", "string", _q, '""')
    tier_fn("ColorName", "color", "string", _q, '""')
    tier_fn("Weight", "weight")
    w("int LootD_RarityAffMin(int nI)")
    w("{")
    w("    switch (nI)")
    w("    {")
    for i, t in enumerate(tiers):
        w("        case %d: return %d;" % (i, t["affixes"][0]))
    w("    }")
    w("    return 0;")
    w("}")
    w("")
    w("int LootD_RarityAffMax(int nI)")
    w("{")
    w("    switch (nI)")
    w("    {")
    for i, t in enumerate(tiers):
        w("        case %d: return %d;" % (i, t["affixes"][1]))
    w("    }")
    w("    return 0;")
    w("}")
    w("")
    tier_fn("Downside", "downside_chance")
    tier_fn("DownPct", "downside_budget_pct")
    tier_fn("Unid", "unidentified_chance")
    tier_fn("UpOne", "upgrade_one")
    tier_fn("UpTwo", "upgrade_two")
    tier_fn("Named", "named_chance")
    tier_fn("RollBias", "roll_bias")
    # Phase 5: gem sockets a rolled item of the tier gets ([min, max]).
    for fn, idx in (("SockMin", 0), ("SockMax", 1)):
        L.extend(_switch_fn("int LootD_Rarity%s(int nI)" % fn,
                            [(i, t.get("sockets", [0, 0])[idx]) for i, t in enumerate(tiers)], "0", str))
    w("// Value budget (gp) for rarity nI at loot level nLvl, before the downside bonus.")
    w("int LootD_RarityBudget(int nI, int nLvl)")
    w("{")
    w("    switch (nI)")
    w("    {")
    for i, t in enumerate(tiers):
        w("    case %d:" % i)
        L.extend(_interp_body(lm.curve(t["budget"])))
    w("    }")
    w("    return 0;")
    w("}")
    w("")

    # -- levels
    w("// Creature CR -> loot level (loot/levels.json cr_points).")
    w("int LootD_LevelForCR(float fCR)")
    w("{")
    pts = data["levels"]["cr_points"]
    w("    if (fCR <= %s) return %d;" % (_f(pts[0][0]), pts[0][1]))
    for (x0, y0), (x1, y1) in zip(pts, pts[1:]):
        w("    if (fCR <= %s) return FloatToInt(%s + %s * (fCR - %s) / %s);"
          % (_f(x1), _f(y0), _f(y1 - y0), _f(x0), _f(x1 - x0)))
    w("    return %d;" % pts[-1][1])
    w("}")
    w("")

    # -- categories / profiles
    L.extend(_switch_fn("string LootD_CatName(int nI)", list(enumerate(cats)), '""', _q))
    pnames = list(profiles)
    w("// Profile name -> index (-1 = unknown).")
    w("int LootD_ProfileIndex(string sProfile)")
    w("{")
    for i, n in enumerate(pnames):
        w("    if (sProfile == %s) return %d;" % (_q(n), i))
    w("    return -1;")
    w("}")
    w("")
    L.extend(_switch_fn("string LootD_ProfileName(int nI)", list(enumerate(pnames)), '""', _q))
    w("int LootD_ProfileCatWeight(int nProfile, int nCat)")
    w("{")
    w("    switch (nProfile * 100 + nCat)")
    w("    {")
    for i, n in enumerate(pnames):
        for c, cn in enumerate(cats):
            v = profiles[n]["categories"].get(cn, 0)
            if v:
                w("        case %d: return %d;" % (i * 100 + c, v))
    w("    }")
    w("    return 0;")
    w("}")
    w("")
    L.extend(_switch_fn("int LootD_ProfileRolls(int nI)",
                        [(i, profiles[n].get("rolls", 1)) for i, n in enumerate(pnames)], "1", str))
    L.extend(_switch_fn("int LootD_ProfileFloor(int nI)",
                        [(i, profiles[n].get("rarity_floor", 0)) for i, n in enumerate(pnames)], "0", str))
    for fn, key, dflt in (("GearChance", "gear_chance", "1000"), ("GoldPct", "gold_pct", "0"),
                          ("GemChance", "gem_chance", "0"),
                          ("SockGemChance", "socket_gem_chance", "0")):
        L.extend(_switch_fn("int LootD_Profile%s(int nI)" % fn,
                            [(i, lm.prof_get(profiles[n], key)) for i, n in enumerate(pnames)], dflt, str))
    w("// TRUE when profile nProfile may roll base row nBase (its optional \"bases\" filter).")
    w("int LootD_ProfileBaseOk(int nProfile, int nBase)")
    w("{")
    w("    switch (nProfile)")
    w("    {")
    for i, n in enumerate(pnames):
        allowed = profiles[n].get("bases")
        if not allowed:
            continue
        w("    case %d:" % i)
        w("        switch (nBase)")
        w("        {")
        for b in allowed:
            w("            case %d: return TRUE;" % b)
        w("        }")
        w("        return FALSE;")
    w("    }")
    w("    return TRUE;")
    w("}")
    w("")
    for fn, idx in (("ConsMin", 0), ("ConsMax", 1)):
        L.extend(_switch_fn("int LootD_Profile%s(int nI)" % fn,
                            [(i, lm.prof_get(profiles[n], "consumables")[idx]) for i, n in enumerate(pnames)],
                            "0", str))

    # -- container scripts + area levels (Phase 3)
    scripts = data["sources"].get("scripts", {})
    w("// Container script -> its loot profile (\"\" = not a loot container script).")
    w("string LootD_ScriptProfile(string sScript)")
    w("{")
    for sn, ent in scripts.items():
        w("    if (sScript == %s) return %s;" % (_q(sn), _q(ent["profile"])))
    w('    return "";')
    w("}")
    w("")
    areas = data["area_levels"]["areas"]
    w("// Area resref -> loot level (loot/area_levels.json; 0 = no level).")
    w("int LootD_AreaLevel(string sArea)")
    w("{")
    for a, e in areas.items():
        if e.get("level"):
            w("    if (sArea == %s) return %d;" % (_q(a), e["level"]))
    w("    return 0;")
    w("}")
    w("")

    # -- wishlist (Phase 6, sources.json "wishlist"; read by loot_inc Loot_WishPick)
    wl = lm.wishlist_cfg(data)
    w("// Loot wishlist (Phase 6, loot/sources.json \"wishlist\").")
    w("const int LOOTD_WISH_MAX = %d;" % wl["picks"])
    w("const int LOOTD_WISH_CHANCE = %d;" % wl["chance"])
    w("const int LOOTD_WISH_FOCUS_W = %d;" % wl["focus_weight"])
    w("")
    base_rows = sorted((b["base"], cats.index(c)) for c in cats for b in bases[c])
    w("// Loot base item row -> category index (LootD_CatName), -1 = not a loot base.")
    L.extend(_switch_fn("int LootD_BaseCat(int nI)", base_rows, "-1", str))
    bi = costs["baseitems"]
    def feat_list(row, key):
        return "|" + "".join("%d|" % f for f in bi[str(row)].get(key, []))
    wrows = [r for r, ci in base_rows if cats[ci] in lm.WISH_PROF_CATS]
    w("// Weapon-focus family feats of a loot base ('|feat|feat|', baseitems.2da")
    w("// WeaponFocusFeat .. WeaponOfChoiceFeat) - wishlist Auto tier 1.")
    L.extend(_switch_fn("string LootD_BaseFocusFeats(int nI)",
                        [(r, feat_list(r, "focus_feats")) for r in wrows], '"|"', _q))
    w("// Proficiency feats of a loot base, any one of which lets a character use it")
    w("// ('|' = none needed; baseitems.2da ReqFeat0-4) - wishlist Auto tier 2.")
    L.extend(_switch_fn("string LootD_BaseReqFeats(int nI)",
                        [(r, feat_list(r, "req_feats")) for r in wrows], '"|"', _q))
    w("// TRUE for a class row that casts spells (classes.2da SpellCaster).")
    w("int LootD_ClassCaster(int nI)")
    w("{")
    w("    switch (nI)")
    w("    {")
    for c in costs["caster_classes"]:
        w("        case %d:" % c)
    w("            return TRUE;")
    w("    }")
    w("    return FALSE;")
    w("}")
    w("")

    # -- creature drops (Phase 4)
    cc = lm.creatures_cfg(data)
    classes = cc["classes"]
    w("// Creature drops (loot/sources.json \"creatures\"), read by loot_ondeath.nss.")
    for i, n in enumerate(lm.CREATURE_CLASSES):
        w("const int LOOTD_CLASS_%s = %d;" % (n.upper(), i))
    w("const int LOOTD_ELITE_MARGIN = %d;" % cc["elite_margin"])
    w("const int LOOTD_BOSS_EXTRA_CR = %d;" % classes["boss"].get("extra_roll_cr", 0))
    w("const int LOOTD_BOSS_NAMED = %d;" % classes["boss"].get("named_chance", 0))
    w("// A boss's socket gem has this tier floor (loot/gems.json boss_floor, Phase 5).")
    w("const int LOOTD_GEM_BOSS_FLOOR = %d;" % data["gems"].get("boss_floor", 0))
    fate = lm.tokens_cfg(data)
    w("// The Shard of Fate (loot/tokens.json \"fate\", Phase 7): blueprint/tag, boss")
    w("// drop chance per mille, bonus-roll prompt timeout and lockout (seconds), and")
    w("// the profile a bonus roll draws from.")
    w("const string LOOTD_FATE_RESREF = %s;" % _q(fate.get("resref", "")))
    w("const int LOOTD_FATE_BOSS_CHANCE = %d;" % fate.get("boss_chance", 0))
    w("const int LOOTD_FATE_TIMEOUT = %d;" % fate.get("bonus_timeout_s", 60))
    w("const int LOOTD_FATE_LOCKOUT = %d;" % fate.get("lockout_s", 86400))
    w("const string LOOTD_FATE_PROFILE = %s;" % _q(fate.get("bonus_profile", "boss")))
    w("const int LOOTD_LIST_NONE = 0;")
    w("const int LOOTD_LIST_ELITE = 1;")
    w("const int LOOTD_LIST_NOT_ELITE = 2;")
    w("const int LOOTD_LIST_NEVER = 3;")
    w("")
    L.extend(_switch_fn("int LootD_CreatureChance(int nI)",
                        [(i, classes[n]["chance"]) for i, n in enumerate(lm.CREATURE_CLASSES)], "0", str))
    L.extend(_switch_fn("int LootD_CreatureGemChance(int nI)",
                        [(i, classes[n].get("gem_chance", 0)) for i, n in enumerate(lm.CREATURE_CLASSES)],
                        "0", str))
    L.extend(_switch_fn("string LootD_CreatureProfile(int nI)",
                        [(i, classes[n]["profile"]) for i, n in enumerate(lm.CREATURE_CLASSES)], '""', _q))
    w("// A creature resref's hand-listing: elite_include / elite_exclude / exclude.")
    w("int LootD_CreatureListed(string sResRef)")
    w("{")
    for key, const in (("exclude", "LOOTD_LIST_NEVER"), ("elite_include", "LOOTD_LIST_ELITE"),
                       ("elite_exclude", "LOOTD_LIST_NOT_ELITE")):
        for rr in sorted(cc.get(key, {})):
            w("    if (sResRef == %s) return %s;" % (_q(rr), const))
    w("    return LOOTD_LIST_NONE;")
    w("}")
    w("")
    w("// Boss resref (canonical or alias) -> pinned loot level (levels.json boss_overrides; 0 = none).")
    w("int LootD_BossLevel(string sResRef)")
    w("{")
    over = data["levels"].get("boss_overrides", {})
    if over:
        boss_map = lm.boss_resrefs()
        for rr in sorted(boss_map):
            if boss_map[rr] in over:
                w("    if (sResRef == %s) return %d;" % (_q(rr), over[boss_map[rr]]))
    w("    return 0;")
    w("}")
    w("")
    w("// Registered boss resref (canonical or alias, brd_db.nss) - never a champion.")
    w("int LootD_IsBoss(string sResRef)")
    w("{")
    for rr in sorted(lm.boss_resrefs()):
        w("    if (sResRef == %s) return TRUE;" % _q(rr))
    w("    return FALSE;")
    w("}")
    w("")
    ch = lm.champions_cfg(data)
    w("// Champions (sources.json creatures.champions), read by loot_champion.nss.")
    for k in ("chance", "hp_pct", "ab", "damage", "ac", "saves"):
        w("const int LOOTD_CHAMP_%s = %d;" % (k.upper(), ch[k]))
    w("const string LOOTD_CHAMP_PREFIX = %s;" % _q(ch["name_prefix"]))
    w("// Area resref -> per-mille champion chance, where it differs from LOOTD_CHAMP_CHANCE")
    w("// (lower where the area already has natural elites; loot_model.area_champion_chances).")
    w("int LootD_AreaChampion(string sArea)")
    w("{")
    for area, pm in lm.area_champion_chances(data).items():
        if pm != ch["chance"]:
            w("    if (sArea == %s) return %d;" % (_q(area), pm))
    w("    return LOOTD_CHAMP_CHANCE;")
    w("}")
    w("")
    w("// TRUE for a faction id (NWNX_Creature_GetFaction) whose reputation toward PCs is")
    w("// <= 10 in repute.fac - the same \"hostile\" the area loot levels use.")
    L.extend(_switch_fn("int LootD_IsHostileFaction(int nI)",
                        [(f, "TRUE") for f in sorted(lm.hostile_factions())], "FALSE", str))

    # -- consumables + treasure gems (Phase 3)
    cons = data["consumables"]["items"]
    w("// Consumables pool (loot/consumables.json), packed: entry i is CONS_ROW characters")
    w("// at (i %% %d) * CONS_ROW of chunk i / %d - min level (2) max level (2) weight (4)" % (CONS_CHUNK, CONS_CHUNK))
    w("// stack lo (2) stack hi (2) resref (16, '|'-padded).  A switch with one case per")
    w("// entry would be a linear compare chain inside a weighted-pick loop - TMI territory.")
    w("const int LOOTD_CONS_COUNT = %d;" % len(cons))
    w("const int LOOTD_CONS_ROW = %d;" % CONS_ROW)
    w("const int LOOTD_CONS_CHUNK = %d;" % CONS_CHUNK)
    w("")
    chunks = []
    for k in range(0, len(cons), CONS_CHUNK):
        chunks.append("".join(cons_row(c) for c in cons[k:k + CONS_CHUNK]))
    L.extend(_switch_fn("string LootD_ConsChunk(int nI)", list(enumerate(chunks)), '""', _q))
    gems = data["treasure"]["gems"]
    G = list(enumerate(gems))
    w("const int LOOTD_GEM_COUNT = %d;" % len(gems))
    w("")
    L.extend(_switch_fn("string LootD_GemResRef(int nI)", [(i, g["resref"]) for i, g in G], '""', _q))
    L.extend(_switch_fn("int LootD_GemValue(int nI)", [(i, g["value"]) for i, g in G], "0", str))

    # -- bases
    L.extend(_switch_fn("int LootD_BaseCount(int nI)",
                        [(c, len(bases.get(cn, []))) for c, cn in enumerate(cats)], "0", str))
    for fn, key, fmt in (("Row", "base", str), ("Weight", "weight", str)):
        w("int LootD_Base%s(int nCat, int nIdx)" % fn)
        w("{")
        w("    switch (nCat * 100 + nIdx)")
        w("    {")
        for c, cn in enumerate(cats):
            for k, b in enumerate(bases.get(cn, [])):
                w("        case %d: return %s;" % (c * 100 + k, fmt(b[key])))
        w("    }")
        w("    return %s;" % ("-1" if key == "base" else "0"))
        w("}")
        w("")
    allb = [b for cn in cats for b in bases.get(cn, [])]
    L.extend(_switch_fn("string LootD_BaseName(int nI)",
                        [(b["base"], b["name"]) for b in allb], '""', _q))
    L.extend(_switch_fn("int LootD_BaseModelType(int nI)",
                        [(b["base"], costs["baseitems"][str(b["base"])]["model_type"]) for b in allb],
                        "-1", str))
    L.extend(_switch_fn("int LootD_DonorCount(int nI)",
                        [(b["base"], len(b.get("donors", []))) for b in allb], "0", str))
    w("// Appearance donor nIdx of base row nBase: comma-separated model parts")
    w("// (1 = simple, 3 = weapon bottom/middle/top, 19 = ITEM_APPR_ARMOR_MODEL_* order).")
    w("string LootD_Donor(int nBase, int nIdx)")
    w("{")
    w("    switch (nBase)")
    w("    {")
    for b in allb:
        if not b.get("donors"):
            continue
        w("    case %d:" % b["base"])
        w("        switch (nIdx)")
        w("        {")
        for k, dn in enumerate(b["donors"]):
            w("            case %d: return %s;" % (k, _q(",".join(str(x) for x in dn))))
        w("        }")
        w("        break;")
    w("    }")
    w('    return "";')
    w("}")
    w("")

    # -- affixes
    A = list(enumerate(affixes))
    L.extend(_switch_fn("string LootD_AffixId(int nI)", [(i, a["id"]) for i, a in A], '""', _q))
    L.extend(_switch_fn("int LootD_AffixType(int nI)", [(i, a["type"]) for i, a in A], "-1", str))
    L.extend(_switch_fn("int LootD_AffixSub(int nI)", [(i, a.get("sub") or 0) for i, a in A], "0", str))
    L.extend(_switch_fn("int LootD_AffixWeight(int nI)", [(i, a["weight"]) for i, a in A], "0", str))
    L.extend(_switch_fn("int LootD_AffixMinLevel(int nI)",
                        [(i, a.get("min_level", 1)) for i, a in A], "1", str))
    L.extend(_switch_fn("int LootD_AffixIsDown(int nI)",
                        [(i, 1 if a["role"] == "downside" else 0) for i, a in A], "0", str))
    L.extend(_switch_fn("string LootD_AffixGroup(int nI)", [(i, a["group"]) for i, a in A], '""', _q))
    L.extend(_switch_fn("string LootD_AffixCats(int nI)",
                        [(i, "|" + "|".join(a["cats"]) + "|") for i, a in A], '""', _q))
    L.extend(_switch_fn("string LootD_AffixPrefix(int nI)",
                        [(i, a.get("prefix", "")) for i, a in A], '""', _q))
    L.extend(_switch_fn("string LootD_AffixSuffix(int nI)",
                        [(i, a.get("suffix", "")) for i, a in A], '""', _q))
    L.extend(_switch_fn("int LootD_AffixLadderLen(int nI)",
                        [(i, len(a["ladder"])) for i, a in A], "0", str))
    w("// Cost-table row at ladder step nStep of affix nAffix (steps ascend in power).")
    w("int LootD_AffixLadder(int nAffix, int nStep)")
    w("{")
    w("    switch (nAffix)")
    w("    {")
    for i, a in A:
        if len(set(a["ladder"])) == 1:
            w("    case %d: return %d;" % (i, a["ladder"][0]))
            continue
        w("    case %d:" % i)
        w("        switch (nStep)")
        w("        {")
        for k, c in enumerate(a["ladder"]):
            w("            case %d: return %d;" % (k, c))
        w("        }")
        w("        break;")
    w("    }")
    w("    return 0;")
    w("}")
    w("")
    for side, idx in (("Lo", 0), ("Hi", 1)):
        w("// %s ladder step of affix nAffix at loot level nLvl." % ("Lowest" if idx == 0 else "Highest"))
        w("int LootD_Affix%s(int nAffix, int nLvl)" % side)
        w("{")
        w("    switch (nAffix)")
        w("    {")
        for i, a in A:
            pts = sorted([int(k), int(v[idx])] for k, v in a["window"].items())
            if len({p[1] for p in pts}) == 1:
                w("    case %d: return %d;" % (i, pts[0][1]))
                continue
            w("    case %d:" % i)
            L.extend(_interp_body(pts))
        w("    }")
        w("    return 0;")
        w("}")
        w("")

    # -- named
    N = list(enumerate(named))
    L.extend(_switch_fn("string LootD_NamedResRef(int nI)", [(i, n["resref"]) for i, n in N], '""', _q))
    L.extend(_switch_fn("int LootD_NamedMin(int nI)", [(i, n["min_level"]) for i, n in N], "99", str))
    L.extend(_switch_fn("int LootD_NamedMax(int nI)", [(i, n["max_level"]) for i, n in N], "0", str))
    L.extend(_switch_fn("int LootD_NamedWeight(int nI)", [(i, n.get("weight", 1)) for i, n in N], "0", str))
    L.extend(_switch_fn("int LootD_NamedBase(int nI)",
                        [(i, lm.named_base(n["resref"]) if lm.named_base(n["resref"]) is not None else -1)
                         for i, n in N], "-1", str))

    # -- property donor (loot_model.DONOR_TYPES)
    w("// The donor item: a generated blueprint (%s) carrying every property whose" % lm.DONOR_RESREF)
    w("// NWScript constructor rejects this module's extended cost rows (loot_model.DONOR_TYPES:")
    for t in sorted(lm.DONOR_TYPES):
        w("//   type %d - %s)." % (t, lm.DONOR_TYPES[t]))
    w("// Created once in FORGE_VAULT and cached on the module.")
    w("object Loot_IPDonor()")
    w("{")
    w("    object oMod = GetModule();")
    w("    object oDonor = GetLocalObject(oMod, \"LOOT_IPDONOR\");")
    w("    if (GetIsObjectValid(oDonor)) return oDonor;")
    w("    object oVault = GetObjectByTag(\"FORGE_VAULT\");")
    w("    if (!GetIsObjectValid(oVault)) return OBJECT_INVALID;")
    w("    oDonor = CreateItemOnObject(\"%s\", oVault);" % lm.DONOR_RESREF)
    w("    SetLocalObject(oMod, \"LOOT_IPDONOR\", oDonor);")
    w("    return oDonor;")
    w("}")
    w("")
    w("// The donor's property (nType, nSub, nCost), or an invalid property.")
    w("itemproperty Loot_DonorIP(int nType, int nSub, int nCost)")
    w("{")
    w("    itemproperty ip;")
    w("    object oDonor = Loot_IPDonor();")
    w("    if (!GetIsObjectValid(oDonor)) return ip;")
    w("    ip = GetFirstItemProperty(oDonor);")
    w("    while (GetIsItemPropertyValid(ip))")
    w("    {")
    w("        if (GetItemPropertyType(ip) == nType && GetItemPropertySubType(ip) == nSub")
    w("            && GetItemPropertyCostTableValue(ip) == nCost)")
    w("            return ip;")
    w("        ip = GetNextItemProperty(oDonor);")
    w("    }")
    w("    return ip;")
    w("}")
    w("")
    # -- property constructor
    w("// Build item property nType from a subtype row and a cost-table row.  One case per")
    w("// loot_model.SUPPORTED_IP entry; anything else returns an invalid property.  A")
    w("// DONOR_TYPES type is copied from the donor item (Loot_DonorIP), falling back to")
    w("// its constructor only when the donor lacks that exact property.")
    w("itemproperty Loot_MakeIP(int nType, int nSub, int nCost)")
    w("{")
    w("    itemproperty ip;")
    w("    switch (nType)")
    w("    {")
    for t in sorted(lm.SUPPORTED_IP):
        label, tmpl = lm.SUPPORTED_IP[t]
        ctor = tmpl.format(sub="nSub", cost="nCost")
        if t in lm.DONOR_TYPES:
            w("        case %d: // %s (donor)" % (t, label))
            w("            ip = Loot_DonorIP(nType, nSub, nCost);")
            w("            if (!GetIsItemPropertyValid(ip)) ip = %s;" % ctor)
            w("            break;")
        else:
            w("        case %d: ip = %s; break; // %s" % (t, ctor, label))
    w("    }")
    w("    return ip;")
    w("}")
    return "\n".join(L) + "\n"


CONS_ROW = 28
CONS_CHUNK = 32
SOCK_PART = 900        # max characters per packed socket-exception string


def socket_include(data=None):
    """unpacked/socket_data_inc.nss: gem families + the existing-item socket rules.
    Read by gem_inc.nss only (never by the chest wrappers)."""
    data = data or lm.load_data()
    g = data["gems"]
    s = data["sockets"]
    fams = g["families"]
    aidx = {a["id"]: i for i, a in enumerate(data["affixes"]["affixes"])}
    cats = list(lm.CATEGORIES)
    L = []
    w = L.append
    w("// socket_data_inc.nss - GENERATED by bin/gen-loot-tables.py. Do not edit.")
    w("// Re-run: python3 bin/gen-loot-tables.py --apply   (source: loot/gems.json, loot/sockets.json)")
    w("// Read by gem_inc.nss (Loot Overhaul Phase 5, sockets and gems). Validated by")
    w("// tests/check_loot_tables.py.  Affix indices refer to loot_data_inc.")
    w("")
    w("const int LOOTD_SOCK_VER = %d;" % s["version"])
    w("const int LOOTD_SOCK_MAX = %d;" % s["max_sockets"])
    w("const int LOOTD_SOCK_DEFAULT = %d;" % s["default"])
    w("const int LOOTD_GEMFAM_COUNT = %d;" % len(fams))
    w("const int LOOTD_GEMTIER_COUNT = %d;" % len(g["tiers"]))
    w('const string LOOTD_GEM_PREFIX = "%s";' % lm.GEM_PREFIX)
    w("")
    F = list(enumerate(fams))
    L.extend(_switch_fn("string LootD_GemFamId(int nI)", [(i, f["id"]) for i, f in F], '""', _q))
    w("// Gem family id -> index (-1 = unknown).")
    w("int LootD_GemFamIndex(string sId)")
    w("{")
    for i, f in F:
        w("    if (sId == %s) return %d;" % (_q(f["id"]), i))
    w("    return -1;")
    w("}")
    w("")
    L.extend(_switch_fn("string LootD_GemFamStone(int nI)", [(i, f["stone"]) for i, f in F], '""', _q))
    L.extend(_switch_fn("string LootD_GemFamEffect(int nI)", [(i, f["effect"]) for i, f in F], '""', _q))
    L.extend(_switch_fn("int LootD_GemFamWeight(int nI)", [(i, f["weight"]) for i, f in F], "0", str))
    L.extend(_switch_fn("int LootD_GemFamAffixCount(int nI)", [(i, len(f["affixes"])) for i, f in F], "0", str))
    L.extend(_switch_fn("int LootD_GemFamLadderLen(int nI)", [(i, len(f["ladder"])) for i, f in F], "0", str))
    afx = data["affixes"]["affixes"]
    conv = {"Affix": lambda v: aidx[v],
            "Type": lambda v: afx[aidx[v]]["type"],
            "Sub": lambda v: -1 if afx[aidx[v]].get("sub") is None else afx[aidx[v]]["sub"],
            "Ladder": lambda v: v, "Steps": lambda v: v}
    w("// Per family: nK-th affix (loot_data_inc index), its property type and subtype")
    w("// (-1 = the type has none), ladder rung nK (cost row) and steps for tier nK.")
    for fn, key in (("Affix", "affixes"), ("Type", "affixes"), ("Sub", "affixes"),
                    ("Ladder", "ladder"), ("Steps", "steps")):
        w("int LootD_GemFam%s(int nFam, int nK)" % fn)
        w("{")
        w("    switch (nFam * 100 + nK)")
        w("    {")
        for i, f in F:
            for k, v in enumerate(f[key]):
                w("        case %d: return %d;" % (i * 100 + k, conv[fn](v)))
        w("    }")
        w("    return %s;" % ("-1" if key == "affixes" else "0"))
        w("}")
        w("")
    L.extend(_switch_fn("string LootD_GemTierWord(int nI)",
                        [(i, x["word"]) for i, x in enumerate(g["tiers"])], '""', _q))
    for fn, key in (("Floor", "floor"), ("Ceil", "ceiling")):
        w("// Gem tier %s at loot level nLvl (gems.json level_bands)." % key)
        w("int LootD_GemBand%s(int nLvl)" % fn)
        w("{")
        for b in reversed(g["level_bands"]):
            w("    if (nLvl >= %d) return %d;" % (b["min_level"], b[key]))
        w("    return 0;")
        w("}")
        w("")
    w("// 2 x average damage of an iprp_damagecost row (hak_2da/iprp_damagecost.2da).")
    L.extend(_switch_fn("int LootD_DmgPower(int nI)", sorted(lm.damage_power().items()), "0", str))
    w("// Socketable base item row -> category index (LootD_CatName), -1 = never socketed.")
    L.extend(_switch_fn("int LootD_SockBaseCat(int nI)",
                        sorted((b, cats.index(c)) for b, c in lm.socket_base_categories(data).items()),
                        "-1", str))
    exc = lm.socket_exceptions(data)
    groups = collections.OrderedDict()
    for rr in sorted(exc):
        groups.setdefault(rr[0], []).append("%s:%d|" % (rr, exc[rr]))
    w("// Module items whose socket count is not the eligible default, packed by the")
    w("// resref's first character into parts of at most %d characters: '|<resref>:<n>|...'." % SOCK_PART)
    w("// Gem_SocketMax searches them with FindSubString; an empty string ends a character's parts.")
    w("const int LOOTD_SOCK_EXCEPTIONS = %d;" % len(exc))
    w("string LootD_SockList(string sFirst, int nPart)")
    w("{")
    for ch, items in groups.items():
        parts, cur = [], "|"
        for it in items:
            if len(cur) + len(it) > SOCK_PART:
                parts.append(cur)
                cur = "|"
            cur += it
        parts.append(cur)
        w("    if (sFirst == %s)" % _q(ch))
        w("    {")
        for k, s_ in enumerate(parts):
            w("        if (nPart == %d) return %s;" % (k, _q(s_)))
        w('        return "";')
        w("    }")
    w('    return "";')
    w("}")
    return "\n".join(L) + "\n"


def write_gem_blueprints(data):
    stale, orphans = lm.gem_blueprint_problems(data)
    fams = {f["id"]: f for f in lm.gem_families(data)}
    for rr in stale:
        fid, tier = rr[len(lm.GEM_PREFIX):].rsplit("_", 1)
        exp = lm.gem_uti(data, fams[fid], int(tier))
        p = lm.UNPACKED / (rr + ".uti.json")
        if p.exists():
            cur = json.loads(p.read_text())
            cur.update({k: exp[k] for k in lm.GEM_UTI_KEYS + ("DescIdentified", "Cost", "Comment")})
            exp = dict(sorted(cur.items()))
        p.write_text(json.dumps(exp, indent=2) + "\n")
    return stale, orphans


def write_donor_blueprint(data):
    """Write unpacked/loot_ipdonor.uti.json, keeping any toolset-only fields."""
    exp = lm.donor_uti(data)
    p = lm.UNPACKED / (lm.DONOR_RESREF + ".uti.json")
    if p.exists():
        cur = json.loads(p.read_text())
        cur.update({k: exp[k] for k in lm.DONOR_UTI_KEYS + ("Comment", "Description",
                                                              "DescIdentified", "LocalizedName")})
        exp = dict(sorted(cur.items()))
    p.write_text(json.dumps(exp, indent=2) + "\n")


def cons_row(c):
    lo, hi = c.get("stack", [1, 1])
    row = "%02d%02d%04d%02d%02d%s" % (c["min_level"], c["max_level"], c.get("weight", 1), lo, hi,
                                      c["resref"].ljust(16, "|"))
    assert len(row) == CONS_ROW, row
    return row


WRAPPER_MARK = "// GENERATED by bin/gen-loot-tables.py from loot/sources.json \"scripts\""
MODE_TEXT = {
    "refill": ("LootChest_Refill", "a respawning chest: refilled on open once 200 s have passed"),
    "once": ("LootChest_Once", "filled once, on first open or when bashed (the stock behaviour)"),
}
# Stock resource names these wrappers override, for the header comment.
STOCK_PREFIXES = ("nw_o2_", "x0_o2_", "x2_02_")


def wrapper_nss(name, ent):
    fn, what = MODE_TEXT[ent["mode"]]
    out = ["// %s.nss" % name,
           WRAPPER_MARK + ". Do not edit:",
           "// change the table, then python3 bin/gen-loot-tables.py --apply.",
           "//",
           "// Loot Overhaul Phase 3 (roadmap rng-based-gear-diablo-world-of-warcraft-style):",
           "// rolled loot, profile '%s', at the area's loot level - %s." % (ent["profile"], what)]
    if name.startswith(STOCK_PREFIXES):
        out.append("// Local override of the stock BioWare treasure script of the same name.")
    out += ['#include "loot_chest_inc"', "", "void main()", "{",
            '    %s("%s");' % (fn, ent["profile"]), "}", ""]
    return "\n".join(out)


def wrapper_problems(data):
    """(stale-or-missing, orphaned) generated wrapper scripts."""
    scripts = data["sources"].get("scripts", {})
    stale = []
    for name, ent in scripts.items():
        if ent["mode"] == "custom":
            continue          # hand-written; loot_model.validate checks it names its profile
        p = lm.UNPACKED / (name + ".nss")
        if not p.exists() or p.read_text() != wrapper_nss(name, ent):
            stale.append(name)
    orphans = []
    for p in sorted(lm.UNPACKED.glob("*.nss")):
        n = p.name[:-4]
        if n not in scripts and WRAPPER_MARK in p.read_text(errors="replace")[:400]:
            orphans.append(n)
    return stale, orphans


def write_wrappers(data):
    n = 0
    for name, ent in data["sources"].get("scripts", {}).items():
        if ent["mode"] == "custom":
            continue
        p = lm.UNPACKED / (name + ".nss")
        text = wrapper_nss(name, ent)
        if not p.exists() or p.read_text() != text:
            p.write_text(text)
            n += 1
    return n


def _f(x):
    s = repr(float(x))
    return s if "e" not in s else "%.6f" % float(x)


def main():
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--apply", action="store_true", help="write unpacked/loot_data_inc.nss")
    ap.add_argument("--refresh-costs", action="store_true", help="re-snapshot loot/_costs.json")
    ap.add_argument("--harvest-donors", action="store_true", help="refill bases.json donors")
    a = ap.parse_args()
    if a.refresh_costs:
        refresh_costs()
    if a.harvest_donors:
        harvest_donors()
    data = lm.load_data()
    errs = lm.validate(data)
    if errs:
        print("loot data has %d problem(s):" % len(errs))
        for e in errs:
            print("  - " + e)
        return 1
    text = nss_include(data)
    cur = lm.INCLUDE.read_text() if lm.INCLUDE.exists() else None
    stext = socket_include(data)
    scur = lm.SOCKET_INCLUDE.read_text() if lm.SOCKET_INCLUDE.exists() else None
    stale, orphans = wrapper_problems(data)
    gstale, gorphans = lm.gem_blueprint_problems(data)
    if orphans:
        print("generated wrapper(s) no longer in sources.json scripts - delete them or add "
              "them back: " + ", ".join(o + ".nss" for o in orphans))
    if gorphans:
        print("gem blueprint(s) no longer in gems.json - delete them or add the family back: "
              + ", ".join(o + ".uti.json" for o in gorphans))
    bad = 1 if (orphans or gorphans) else 0
    dprobs = lootdoc.problems(data)
    dstale = lm.donor_stale(data)
    if cur == text and scur == stext and not stale and not gstale and not dprobs and not dstale:
        print("ok: %s, %s, %d container scripts and %d gem blueprints are up to date"
              % (lm.INCLUDE.relative_to(ROOT), lm.SOCKET_INCLUDE.relative_to(ROOT),
                 len(data["sources"].get("scripts", {})),
                 len(lm.gem_families(data)) * len(data["gems"]["tiers"])))
        return bad
    if a.apply:
        if cur != text:
            lm.INCLUDE.write_text(text)
            print("wrote %s (%d lines)" % (lm.INCLUDE.relative_to(ROOT), text.count("\n")))
        if scur != stext:
            lm.SOCKET_INCLUDE.write_text(stext)
            print("wrote %s (%d lines)" % (lm.SOCKET_INCLUDE.relative_to(ROOT), stext.count("\n")))
        if stale:
            print("wrote %d container script(s): %s" % (write_wrappers(data), ", ".join(stale)))
        if gstale:
            write_gem_blueprints(data)
            print("wrote %d gem blueprint(s) - file new ones into the palette with "
                  "python3 bin/file-palette-orphans.py --apply" % len(gstale))
        if dstale:
            write_donor_blueprint(data)
            print("wrote unpacked/%s.uti.json (%d properties) - file it into the palette with "
                  "python3 bin/file-palette-orphans.py --apply"
                  % (lm.DONOR_RESREF, len(lm.donor_props(data))))
        if dprobs:
            try:
                lootdoc.apply(data)
            except lootdoc.DocError as e:
                print("loot wiki tables: " + str(e))
                return 1
            print("wrote the loot tables in %s - now run python3 bin/gen-customizations-hub.py"
                  % lootdoc.PAGE.relative_to(ROOT))
        return bad
    if cur != text:
        print("%s is stale - re-run with --apply" % lm.INCLUDE.relative_to(ROOT))
    if scur != stext:
        print("%s is stale - re-run with --apply" % lm.SOCKET_INCLUDE.relative_to(ROOT))
    if stale:
        print("container script(s) stale or missing - re-run with --apply: " + ", ".join(stale))
    if gstale:
        print("gem blueprint(s) stale or missing - re-run with --apply: " + ", ".join(gstale[:8])
              + (" ..." if len(gstale) > 8 else ""))
    if dstale:
        print("unpacked/%s.uti.json stale or missing - re-run with --apply" % lm.DONOR_RESREF)
    for d in dprobs:
        print(d)
    return 1


if __name__ == "__main__":
    sys.exit(main())
