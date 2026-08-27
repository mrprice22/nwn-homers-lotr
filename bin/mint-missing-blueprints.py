#!/usr/bin/env python3
"""Mint blueprints for placed creatures whose blueprint resref resolves nowhere.

se_respawn_inc respawns a dead static creature with

    CreateObject(OBJECT_TYPE_CREATURE, GetResRef(self), spawnLoc, FALSE, GetTag(self))

so the resref has to resolve to a real blueprint. Some placements name a resref
that exists in NO container -- not unpacked/, not the base game, not CEP. Those
creatures are placed and killable, they run an OnDeath that tries to respawn
them, and CreateObject returns nothing: the creature is gone until the next
server restart. It looks exactly like "this mob never respawns", but the cause
is a missing blueprint rather than a missing respawn call.

The fix is to bake the blueprint the module has been missing, out of the
placement's own GFF struct (a placement IS a complete creature record). The
resref is unchanged -- nothing resolved it before -- so no placement, tag,
script or quest lookup moves.

Where several placements share such a resref with different identities, the
blueprint is baked from the most common one and the rest are left to
bin/split-divergent-creatures.py, which can now see a local base to compare
against.

    python3 bin/mint-missing-blueprints.py --dry-run
    python3 bin/mint-missing-blueprints.py --apply

The set of resrefs that resolve outside the module is read from
tests/respawn_external_blueprints.json (refresh it with
bin/audit-creature-respawn.py --refresh-external, which needs the NWN install).
"""
import argparse
import copy
import importlib.util
import json
import sys
from collections import Counter, defaultdict
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
UNPACKED = ROOT / "unpacked"
EXTERNAL = ROOT / "tests" / "respawn_external_blueprints.json"

_spec = importlib.util.spec_from_file_location(
    "split_divergent", ROOT / "bin" / "split-divergent-creatures.py")
_sd = importlib.util.module_from_spec(_spec)
_spec.loader.exec_module(_sd)

sys.path.insert(0, str(ROOT / "bin"))
import boss_index as bi                                     # noqa: E402
from boss_index import gv, locstr                            # noqa: E402

_gspec = importlib.util.spec_from_file_location(
    "gen_boss_registry", ROOT / "bin" / "gen-boss-registry.py")
_gbr = importlib.util.module_from_spec(_gspec)
_gspec.loader.exec_module(_gbr)


def external_resrefs():
    if not EXTERNAL.exists():
        return set()
    return {r.lower() for r in json.loads(EXTERNAL.read_text())["resolves_outside_module"]}


def palette_id_for_race(race, _cache={}):
    """Best PaletteID for a race, learned from the blueprints already filed.

    The toolset places a blueprint by its PaletteID and regenerates the whole
    custom palette from PaletteIDs on every save, so this only decides which
    toolset folder the new leaf lands in -- but a blanket default would drop
    every elf, halfling and dryad into "NPCs > Humans". Only a clear plurality
    counts; anything weaker falls back to 44 (NPCs > Humans).
    """
    if not _cache:
        by_race = defaultdict(Counter)
        for utc in UNPACKED.glob("*.utc.json"):
            d = json.loads(utc.read_text())
            pid = gv(d.get("PaletteID"))
            if pid is not None:
                by_race[gv(d.get("Race"))][pid] += 1
        for r, counts in by_race.items():
            top = counts.most_common(2)
            best, n = top[0]
            runner = top[1][1] if len(top) > 1 else 0
            _cache[r] = best if n >= 5 and n >= 2 * runner else 44
        _cache[None] = 44
    return _cache.get(race, 44)


def identity(struct):
    """What a respawn would have to reproduce: shown name + faction + combat."""
    name = (locstr(struct.get("FirstName")) + " "
            + locstr(struct.get("LastName"))).strip()
    return (name, gv(struct.get("FactionID")), _sd.combat_key(struct))


def collect():
    """resref -> {'identities': {ident: [structs]}, 'areas': Counter}"""
    have = {p.name[:-len(".utc.json")].lower() for p in UNPACKED.glob("*.utc.json")}
    external = external_resrefs()
    groups = defaultdict(lambda: {"identities": defaultdict(list), "areas": Counter()})
    for git in sorted(UNPACKED.glob("*.git.json")):
        area = git.name[:-len(".git.json")]
        data = json.loads(git.read_text())
        for c in gv(data.get("Creature List")) or []:
            rr = (gv(c.get("TemplateResRef")) or "").lower()
            if not rr or rr in have or rr in external:
                continue
            # Only creatures that actually try to respawn matter: the rest are
            # corpse props and unkillable NPCs the ignore list already covers.
            death = (gv(c.get("ScriptDeath")) or "").lower()
            if _gbr._death_respawn_kind(death) != "standard":
                continue
            g = groups[rr]
            g["identities"][identity(c)].append(c)
            g["areas"][area] += 1
    return groups


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--apply", action="store_true", help="write the blueprints")
    ap.add_argument("--dry-run", action="store_true")
    args = ap.parse_args()
    if not args.apply:
        args.dry_run = True

    groups = collect()
    if not groups:
        print("mint-missing-blueprints: nothing to do — every respawning "
              "placement resolves to a blueprint")
        return 0

    total = sum(sum(len(v) for v in g["identities"].values()) for g in groups.values())
    print(f"{len(groups)} resref(s) resolve nowhere, covering {total} respawning "
          f"placement(s)\n")
    written = 0
    for rr in sorted(groups):
        g = groups[rr]
        variants = sorted(g["identities"].items(), key=lambda kv: -len(kv[1]))
        (name, faction, _ck), structs = variants[0]
        n = sum(len(v) for v in g["identities"].values())
        extra = (f"  [+{len(variants) - 1} other identit"
                 f"{'y' if len(variants) == 2 else 'ies'}]" if len(variants) > 1 else "")
        areas = ", ".join(f"{a}×{c}" for a, c in g["areas"].most_common(3))
        print(f"  {rr:20s} {name[:30]:30s} {n:3d} placement(s)  {areas}{extra}")

        if args.apply:
            src = copy.deepcopy(structs[0])
            for k in _sd.POSITIONAL:
                src.pop(k, None)
            src["TemplateResRef"] = {"type": "resref", "value": rr}
            if "PaletteID" not in src:
                src["PaletteID"] = {"type": "byte",
                                    "value": palette_id_for_race(gv(src.get("Race")))}
            if (_sd.fld(src, "ScriptSpawn") or "").strip().lower() \
                    not in _sd.spawn_storing_scripts():
                _sd._ensure_no_leash(src)
            ordered = {"__data_type": "UTC "}
            for k in sorted(k for k in src if k != "__data_type"):
                ordered[k] = src[k]
            _sd.write_json(str(UNPACKED / f"{rr}.utc.json"), ordered)
            written += 1

    if args.apply:
        print(f"\nwrote {written} blueprint(s) into unpacked/")
        print("next: python3 bin/split-divergent-creatures.py --dry-run   "
              "(any placement whose identity differs from the baked one)")
        print("      python3 bin/file-palette-orphans.py --apply          "
              "(the palette-coverage gate)")
    else:
        print("\n(dry run — pass --apply to write)")
    return 0


if __name__ == "__main__":
    sys.exit(main())
