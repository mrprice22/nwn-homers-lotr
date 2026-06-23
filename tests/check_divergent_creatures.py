#!/usr/bin/env python3
"""Respawn-override divergence check (build-time smoke test).

The module respawns dead static creatures from their *blueprint*
(`unpacked/se_respawn_inc.nss` → `CreateObject(GetResRef(self), …)`), preserving
only the tag. So any placement whose identity differs from what its blueprint
would re-create silently reverts after the first death — name, faction,
abilities, classes, feats, special abilities, equipment, natural AC, race, or
conversation. (The bug that produced Carn Dum City's "Numanan Numerocks Second
Hand" respawning as the blueprint's "Numarok The Black Hand".)

`bin/split-divergent-creatures.py` fixed every existing case by giving each
diverging placement its own blueprint. This gate keeps it that way:

    LOCAL base (a <base>.utc.json exists):
        every static placement's identity must equal the blueprint's identity.
    STOCK base (no local .utc — a CEP/base-game blueprint):
        all of its static placements must share one identity (we can't read the
        stock baseline, but divergence between placements is provable).

"Identity" mirrors `bin/split-divergent-creatures.py` / nwn-wiki `_creature_key`
plus name, faction and conversation. The helpers below are duplicated from that
script intentionally, matching the standalone style of check_spawn_leash.py.

Scans unpacked/ directly (module-index/ is gitignored and may be absent on a
fresh clone). Exits 0 if all placements are respawn-safe, 1 otherwise.
"""

import glob
import json
import os
import sys
from collections import defaultdict

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
UNPACKED = os.path.join(ROOT, "unpacked")


def fld(struct, key):
    v = struct.get(key) if isinstance(struct, dict) else None
    return v.get("value") if isinstance(v, dict) else None


def loc(v):
    if isinstance(v, dict):
        val = v.get("value")
        if isinstance(val, dict):
            return val.get("0")
    return None


def list_items(struct, key):
    v = struct.get(key)
    if isinstance(v, dict):
        v = v.get("value")
    return v if isinstance(v, list) else []


def combat_key(s):
    abilities = tuple(fld(s, a) for a in ("Str", "Dex", "Con", "Int", "Wis", "Cha"))
    classes = tuple(sorted(
        (fld(cl, "Class"), fld(cl, "ClassLevel")) for cl in list_items(s, "ClassList")))
    feats = tuple(sorted(
        int(fld(f, "Feat")) for f in list_items(s, "FeatList") if fld(f, "Feat") is not None))
    spec = tuple(sorted(
        (fld(x, "Spell"), fld(x, "SpellCasterLevel")) for x in list_items(s, "SpecAbilityList")))
    equip = tuple(sorted(
        (fld(e, "__struct_id"), (fld(e, "EquippedRes") or fld(e, "TemplateResRef") or ""))
        for e in list_items(s, "Equip_ItemList")))
    return (abilities, classes, feats, spec, equip, fld(s, "NaturalAC"), fld(s, "Race"))


def display_name(s):
    return ((loc(s.get("FirstName")) or "") + " " + (loc(s.get("LastName")) or "")).strip()


def identity_key(s):
    return (display_name(s).lower(), fld(s, "FactionID"),
            (fld(s, "Conversation") or "").lower(), combat_key(s))


def local_blueprint(resref, cache):
    if resref not in cache:
        p = os.path.join(UNPACKED, f"{resref}.utc.json")
        cache[resref] = json.load(open(p, encoding="utf-8")) if os.path.exists(p) else None
    return cache[resref]


def main():
    cache = {}
    # base -> list of (area, idx, identity, display_name)
    placements = defaultdict(list)
    for gf in sorted(glob.glob(os.path.join(UNPACKED, "*.git.json"))):
        area = os.path.basename(gf)[:-len(".git.json")]
        try:
            d = json.load(open(gf, encoding="utf-8"))
        except (OSError, json.JSONDecodeError) as e:
            print(f"[divergent-creatures] FAIL: unreadable {area}.git.json: {e}", file=sys.stderr)
            return 1
        cl = d.get("Creature List")
        if not cl:
            continue
        for idx, c in enumerate(cl["value"]):
            base = fld(c, "TemplateResRef")
            if base:
                placements[base].append((area, idx, identity_key(c), display_name(c) or "(unnamed)"))

    failures = []  # (base, kind, detail)
    for base, plist in sorted(placements.items()):
        bp = local_blueprint(base, cache)
        if bp is not None:
            base_ident = identity_key(bp)
            bad = [(a, i, nm) for a, i, ident, nm in plist if ident != base_ident]
            if bad:
                names = sorted({nm for _a, _i, nm in bad})
                where = ", ".join(f"{a}#{i}" for a, i, _nm in bad[:4])
                failures.append((base, "local",
                                 f'{len(bad)} placement(s) differ from blueprint '
                                 f'"{display_name(bp) or base}": {names} @ {where}'))
        else:
            idents = {ident for _a, _i, ident, _nm in plist}
            if len(idents) > 1:
                names = sorted({nm for _a, _i, _id, nm in plist})
                failures.append((base, "stock",
                                 f'stock blueprint placed under {len(idents)} identities: {names}'))

    if failures:
        print(f"[divergent-creatures] FAIL: {len(failures)} blueprint(s) have placements "
              f"that will revert to the blueprint on respawn:", file=sys.stderr)
        for base, kind, detail in failures:
            print(f"  - {base:<20} [{kind}] {detail}", file=sys.stderr)
        print("\nFix: run `python3 bin/split-divergent-creatures.py` to give each diverging "
              "placement its own blueprint (see se_respawn_inc.nss).", file=sys.stderr)
        return 1

    total = sum(len(v) for v in placements.values())
    print(f"[divergent-creatures] OK: all {total} static creature placements respawn faithfully "
          f"({len(placements)} blueprints).")
    return 0


if __name__ == "__main__":
    sys.exit(main())
