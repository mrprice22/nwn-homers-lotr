#!/usr/bin/env python3
"""Set every boss encounter instance's ResetTime to BOSS_RESPAWN_SECONDS.

A placed boss's respawn is a se_respawn_inc DelayCommand, so it picks up
unpacked/boss_tune.nss at compile time. An ENCOUNTER boss's respawn is data:
the ResetTime on its encounter instance inside <area>.git.json. This tool is
what keeps that data in step with the constant, so "all bosses respawn in N
minutes" stays a one-line edit in boss_tune.nss.

Only instances that spawn a registry boss are touched, and only the INSTANCE
(the .ute blueprint is shared with trash encounters - moriabyss has 6 instances,
morialight001 has 13 - and the instance wins at runtime anyway).

Dry-run by default; --apply writes. Re-run bin/gen-boss-registry.py --write
afterwards so the seeded respawn_seconds match, then tests/check_boss_registry.py.
"""
import argparse
import json
import re
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
import boss_index as bi
from boss_index import UNPACKED, gv

SEED_RE = re.compile(r'BRD_SeedBoss\("([^"]+)",[^;]*?"(placed|encounter)"\)')
ALIAS_RE = re.compile(r'BRD_SeedAlias\("([^"]+)",\s*"([^"]+)"\)')


def encounter_boss_resrefs():
    """Registry resrefs that spawn from an encounter, plus their aliases."""
    src = (UNPACKED / "brd_db.nss").read_text()
    enc = {rr for rr, kind in SEED_RE.findall(src) if kind == "encounter"}
    enc |= {rr for rr, canon in ALIAS_RE.findall(src) if canon in enc}
    return enc


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--apply", action="store_true", help="write the .git.json files")
    args = ap.parse_args()

    want = bi.boss_respawn_seconds()
    bosses = encounter_boss_resrefs()
    _placements, enc_slots = bi.build_placement_indices()

    # area -> {encounter index: boss resref} (index into the area's Encounter List)
    targets = {}
    for rr in sorted(bosses):
        for area, _tmpl, e in enc_slots.get(rr, []):
            targets.setdefault(area, {})[id(e)] = rr

    changed = 0
    for area in sorted(targets):
        path = UNPACKED / f"{area}.git.json"
        data = json.loads(path.read_text())
        encs = gv(data.get("Encounter List")) or []
        dirty = False
        for e in encs:
            slots = gv(e.get("CreatureList")) or []
            hit = next((gv(s.get("ResRef")) for s in slots
                        if gv(s.get("ResRef")) in bosses), None)
            if not hit:
                continue
            node = e.get("ResetTime")
            cur = gv(node)
            if cur == want:
                print(f"  ok   {area:20} {gv(e.get('TemplateResRef')):18} "
                      f"{hit:18} ResetTime={cur}")
                continue
            print(f"  SET  {area:20} {gv(e.get('TemplateResRef')):18} "
                  f"{hit:18} ResetTime={cur} -> {want}")
            changed += 1
            if args.apply:
                if isinstance(node, dict) and "value" in node:
                    node["value"] = want
                else:
                    e["ResetTime"] = {"type": "dword", "value": want}
                dirty = True
        if dirty and args.apply:
            path.write_text(json.dumps(data, indent=2, ensure_ascii=False) + "\n")

    print(f"\nBOSS_RESPAWN_SECONDS={want}: "
          f"{changed} encounter instance(s) {'updated' if args.apply else 'need updating'}")
    if changed and not args.apply:
        print("re-run with --apply to write")
    return 0


if __name__ == "__main__":
    sys.exit(main())
