#!/usr/bin/env python3
"""Build gate: the Roll of the Fallen boss registry must match the module.

Parses the BRD_SeedBoss(...) rows out of unpacked/brd_db.nss and checks each
against the unpacked sources:

  * the blueprint <resref>.utc.json exists and its Tag matches the seeded tag
    (instance tag overrides are checked instead where a placement overrides it)
  * placed bosses:    exactly ONE instance across all *.git.json, never inside
                      any encounter, and the tag does not contain "NSP" (which
                      would disable the se_respawn 15-minute respawn)
  * encounter bosses: never placed directly, appear in exactly ONE encounter
                      instance (checking instance-level CreatureList overrides,
                      not the .ute blueprint), that instance spawns at most one
                      creature at a time (MaxCreatures==1), re-arms forever
                      (Respawns==-1, Reset==1), lives in the registry's area,
                      and its ResetTime equals the seeded respawn_seconds
  * boss_alias rows point at a registered canonical resref, and alias
    blueprints exist

Keeps the Well of Eru board honest if respawn times, placements or encounter
definitions change later.
"""
import json
import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
UNPACKED = ROOT / "unpacked"

SEED_RE = re.compile(
    r'BRD_SeedBoss\("(?P<resref>[^"]*)",\s*"(?P<name>[^"]*)",\s*"(?P<tag>[^"]*)",'
    r'\s*"(?P<area>[^"]*)",\s*"(?P<area_name>[^"]*)",\s*(?P<cr>[0-9.]+)f?,'
    r'\s*(?P<respawn>\d+),\s*"(?P<type>placed|encounter)"\)'
)
ALIAS_RE = re.compile(r'BRD_SeedAlias\("(?P<resref>[^"]*)",\s*"(?P<canonical>[^"]*)"\)')


def gv(node):
    return node["value"] if isinstance(node, dict) and "value" in node else node


def main():
    src = (UNPACKED / "brd_db.nss").read_text()
    bosses = [m.groupdict() for m in SEED_RE.finditer(src)]
    aliases = [m.groupdict() for m in ALIAS_RE.finditer(src)]
    if not bosses:
        print("check_boss_registry: no BRD_SeedBoss rows parsed from brd_db.nss")
        return 1

    # Index every placement and every encounter-instance creature slot.
    placements = {}      # resref -> [(area, instance-tag-override or None)]
    enc_slots = {}       # creature resref -> [ (area, enc template, enc struct) ]
    for git in sorted(UNPACKED.glob("*.git.json")):
        area = git.name.replace(".git.json", "")
        data = json.loads(git.read_text())
        for c in gv(data.get("Creature List")) or []:
            placements.setdefault(gv(c.get("TemplateResRef")), []).append(
                (area, gv(c.get("Tag"))))
        for e in gv(data.get("Encounter List")) or []:
            for slot in gv(e.get("CreatureList")) or []:
                enc_slots.setdefault(gv(slot.get("ResRef")), []).append(
                    (area, gv(e.get("TemplateResRef")), e))

    errors = []
    registered = {b["resref"] for b in bosses}

    for b in bosses:
        rr, tag, area, sty = b["resref"], b["tag"], b["area"], b["type"]
        respawn = int(b["respawn"])
        label = f"{rr} ({b['name']})"

        utc = UNPACKED / f"{rr}.utc.json"
        if not utc.exists():
            errors.append(f"{label}: blueprint {rr}.utc.json missing")
            continue
        bp_tag = gv(json.loads(utc.read_text()).get("Tag"))

        placed = placements.get(rr, [])
        slots = enc_slots.get(rr, [])

        if sty == "placed":
            if len(placed) != 1:
                errors.append(f"{label}: placed-boss must have exactly 1 placement, found "
                              f"{len(placed)}: {[a for a, _ in placed]}")
                continue
            if slots:
                errors.append(f"{label}: placed-boss also appears in encounter(s) "
                              f"{[(a, t) for a, t, _ in slots]} — not single-instance")
            p_area, p_tag = placed[0]
            eff_tag = p_tag or bp_tag
            if p_area != area:
                errors.append(f"{label}: registry area '{area}' but placed in '{p_area}'")
            if eff_tag != tag:
                errors.append(f"{label}: registry tag '{tag}' but effective tag '{eff_tag}'")
            if "NSP" in (eff_tag or ""):
                errors.append(f"{label}: tag contains NSP — se_respawn will never respawn it")
        else:  # encounter
            if placed:
                errors.append(f"{label}: encounter-boss is also placed directly in "
                              f"{[a for a, _ in placed]} — not single-instance")
            if bp_tag != tag:
                errors.append(f"{label}: registry tag '{tag}' but blueprint tag '{bp_tag}'")
            # Alias variants share the canonical's encounter; count distinct encounters
            variant_rrs = [rr] + [a["resref"] for a in aliases if a["canonical"] == rr]
            insts = {id(e): (a, t, e) for v in variant_rrs
                     for a, t, e in enc_slots.get(v, [])}
            if len(insts) != 1:
                errors.append(f"{label}: expected exactly 1 encounter instance, found "
                              f"{[(a, t) for a, t, _ in insts.values()]}")
                continue
            e_area, e_tmpl, e = next(iter(insts.values()))
            if e_area != area:
                errors.append(f"{label}: registry area '{area}' but encounter '{e_tmpl}' "
                              f"is in '{e_area}'")
            if gv(e.get("MaxCreatures")) != 1:
                errors.append(f"{label}: encounter '{e_tmpl}' MaxCreatures="
                              f"{gv(e.get('MaxCreatures'))} — more than one can be alive")
            if gv(e.get("Respawns")) != -1 or gv(e.get("Reset")) != 1:
                errors.append(f"{label}: encounter '{e_tmpl}' is not infinitely re-arming "
                              f"(Respawns={gv(e.get('Respawns'))}, Reset={gv(e.get('Reset'))})")
            if gv(e.get("ResetTime")) != respawn:
                errors.append(f"{label}: registry respawn {respawn}s but encounter "
                              f"'{e_tmpl}' ResetTime={gv(e.get('ResetTime'))}")

    for a in aliases:
        if a["canonical"] not in registered:
            errors.append(f"alias {a['resref']}: canonical '{a['canonical']}' not in registry")
        if not (UNPACKED / f"{a['resref']}.utc.json").exists():
            errors.append(f"alias {a['resref']}: blueprint missing")

    if errors:
        print(f"check_boss_registry: {len(errors)} problem(s):")
        for e in errors:
            print(f"  - {e}")
        return 1

    print(f"check_boss_registry: OK — {len(bosses)} bosses "
          f"({sum(1 for b in bosses if b['type'] == 'placed')} placed, "
          f"{sum(1 for b in bosses if b['type'] == 'encounter')} encounter), "
          f"{len(aliases)} aliases verified")
    return 0


if __name__ == "__main__":
    sys.exit(main())
