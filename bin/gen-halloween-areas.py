#!/usr/bin/env python3
"""Generate the Harvest of Shadows (Halloween event) area table.

Writes the block between
  // BEGIN GENERATED HW AREAS  ...  // END GENERATED HW AREAS
in unpacked/hw_areas_inc.nss. Two functions come out of it:

  HW_AreaTier(sResRef)  0 = peaceful (no Hostile/Evil spawns), else 1..6 from
                        the median CR of the area's hostile spawns. A peaceful
                        area gets decaying town pumpkins; a tiered one gets
                        persistent cursed pumpkins scaled to the tier.
  HW_BossHome(i)        the home location of the i-th Roll of the Fallen boss
                        (read from the BRD_SeedBoss block in brd_db.nss), as
                        "area|x|y|z". Boss pumpkin rings are planted there.

Everything is read from unpacked/ directly (placed creature instances and
active encounter pools), never from module-index/, so the table cannot lag a
stale wiki build. tests/check_halloween_areas.py fails the repack if the block
is out of date.

Dry-run by default (prints the tier histogram); --write rewrites the include.
"""
import argparse
import json
import re
import statistics
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
UNPACKED = ROOT / "unpacked"
TARGET = UNPACKED / "hw_areas_inc.nss"
BRD = UNPACKED / "brd_db.nss"

BEGIN = "// BEGIN GENERATED HW AREAS"
END = "// END GENERATED HW AREAS"

HOSTILE_FACTIONS = {1, 5}   # Hostile, Evil (repute.fac.json)

# Module CRs are heavily inflated (a Bree skeleton is 0.5, a Mount Doom one
# 178), so tiers are cut on the module's own scale, not the D&D one.
TIER_CUTS = [(5, 1), (25, 2), (60, 3), (110, 4), (180, 5)]   # else 6

# Hand overrides: resref -> tier (0 = peaceful). The mechanical rule reads
# "no hostile spawns" as peaceful, which is wrong for a fortress whose
# defenders happen to be scripted rather than placed.
OVERRIDES = {
    "bree": 0,   # the town: only hostiles are a graveyard encounter and the dummy
}
# Hostile-faction placements that are not threats (Combat Dummy diagnostic).
IGNORE_TAGS = {"cbd_dummy"}
# Areas never touched at all (event OFF there): the Well of Eru hub, admin
# rooms and the card-game table. Pumpkins in a hub are clutter, not fun.
EXCLUDED = {
    "dmcontrolroom", "dmcloningchamber", "dmeventarea", "dmhq",
    "appearancechange",   # the appearance catalogue room
    "area017",            # Dungeon Solitaire card table
    "prison",             # contraband jail
}


def gv(node):
    return node.get("value") if isinstance(node, dict) else node


def tier_for(cr):
    for cut, tier in TIER_CUTS:
        if cr < cut:
            return tier
    return 6


def area_crs(git):
    crs = []
    for c in gv(git.get("Creature List")) or []:
        if gv(c.get("FactionID")) in HOSTILE_FACTIONS and gv(c.get("Tag")) not in IGNORE_TAGS:
            crs.append(float(gv(c.get("ChallengeRating")) or 0))
    for e in gv(git.get("Encounter List")) or []:
        if not gv(e.get("Active")):
            continue
        if gv(e.get("Faction")) not in HOSTILE_FACTIONS:
            continue
        for s in gv(e.get("CreatureList")) or []:
            crs.append(float(gv(s.get("CR")) or 0))
    return crs


def boss_rows():
    pat = re.compile(r'BRD_SeedBoss\("([^"]+)",\s*"(?:[^"\\]|\\.)*",\s*"[^"]*",\s*"([^"]+)"')
    return pat.findall(BRD.read_text(encoding="utf-8", errors="replace"))


def boss_home(resref, area):
    p = UNPACKED / f"{area}.git.json"
    if not p.exists():
        return None
    git = json.loads(p.read_text())
    for c in gv(git.get("Creature List")) or []:
        if gv(c.get("TemplateResRef")) == resref:
            return (gv(c["XPosition"]), gv(c["YPosition"]), gv(c["ZPosition"]))
    for e in gv(git.get("Encounter List")) or []:
        if not any(gv(s.get("ResRef")) == resref for s in gv(e.get("CreatureList")) or []):
            continue
        sp = gv(e.get("SpawnPointList")) or []
        if sp:
            return (gv(sp[0]["X"]), gv(sp[0]["Y"]), gv(sp[0]["Z"]))
        geo = gv(e.get("Geometry")) or []
        ex, ey, ez = gv(e["XPosition"]), gv(e["YPosition"]), gv(e["ZPosition"])
        if geo:
            return (ex + sum(gv(g["X"]) for g in geo) / len(geo),
                    ey + sum(gv(g["Y"]) for g in geo) / len(geo),
                    ez + sum(gv(g["Z"]) for g in geo) / len(geo))
        return (ex, ey, ez)
    return None


def build():
    tiers = {}
    for p in sorted(UNPACKED.glob("*.git.json")):
        rr = p.name[:-len(".git.json")]
        if rr in EXCLUDED:
            continue
        crs = area_crs(json.loads(p.read_text()))
        tiers[rr] = tier_for(statistics.median(crs)) if crs else 0
    tiers.update(OVERRIDES)

    homes = []
    for resref, area in boss_rows():
        h = boss_home(resref, area)
        if h:
            homes.append((resref, area, h))
    return tiers, homes


def render(tiers, homes):
    out = [BEGIN + " - produced by bin/gen-halloween-areas.py; do not hand-edit."]
    by_tier = {}
    for rr, t in tiers.items():
        by_tier.setdefault(t, []).append(rr)
    # One packed string per tier, searched with FindSubString: a 290-case
    # switch on a string is not a thing NWScript can do.
    out.append("int HW_AreaTier(string sResRef)")
    out.append("{")
    out.append('    string s = "|" + sResRef + "|";')
    for t in sorted(by_tier):
        if t == 0:
            continue
        names = sorted(by_tier[t])
        out.append(f'    if (FindSubString("|{"|".join(names)}|", s) >= 0) return {t};')
    out.append("    return 0;")
    out.append("}")
    out.append("")
    out.append("// No pumpkins and no lighting change at all in these areas.")
    out.append("int HW_AreaExcluded(string sResRef)")
    out.append("{")
    out.append(f'    return FindSubString("|{"|".join(sorted(EXCLUDED))}|", "|" + sResRef + "|") >= 0;')
    out.append("}")
    out.append("")
    out.append(f"const int HW_BOSS_HOME_COUNT = {len(homes)};")
    out.append("")
    out.append("string HW_BossHome(int i)")
    out.append("{")
    out.append("    switch (i)")
    out.append("    {")
    for i, (resref, area, (x, y, z)) in enumerate(homes):
        out.append(f'        case {i}: return "{resref}|{area}|{x:.2f}|{y:.2f}|{z:.2f}";')
    out.append("    }")
    out.append('    return "";')
    out.append("}")
    out.append(END)
    return "\n".join(out)


def splice(text, block):
    a, b = text.find(BEGIN), text.find(END)
    if a < 0 or b < 0:
        sys.exit(f"{TARGET}: generated-block markers not found")
    return text[:a] + block + text[b + len(END):]


def main():
    ap = argparse.ArgumentParser(description=__doc__.split("\n")[0])
    ap.add_argument("--write", action="store_true")
    ap.add_argument("--check", action="store_true", help="exit 1 if stale")
    a = ap.parse_args()
    tiers, homes = build()
    text = TARGET.read_text()
    new = splice(text, render(tiers, homes))
    if a.check:
        if new != text:
            print("hw_areas_inc.nss is stale: run python3 bin/gen-halloween-areas.py --write")
            return 1
        return 0
    hist = {}
    for t in tiers.values():
        hist[t] = hist.get(t, 0) + 1
    print("areas per tier (0 = peaceful):", dict(sorted(hist.items())))
    print(f"boss homes: {len(homes)}")
    if a.write:
        if new != text:
            TARGET.write_text(new)
            print(f"wrote {TARGET.relative_to(ROOT)}")
        else:
            print("up to date")
    return 0


if __name__ == "__main__":
    sys.exit(main())
