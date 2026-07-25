#!/usr/bin/env python3
"""Split divergent creature placements into dedicated blueprints.

Problem
-------
The module respawns dead static creatures with Sir Elric's respawn system
(`unpacked/se_respawn_inc.nss`, called from `nw_c2_default7` OnDeath). That does:

    CreateObject(OBJECT_TYPE_CREATURE, GetResRef(self), spawnLoc, FALSE, GetTag(self))

i.e. it re-instantiates the creature's *blueprint*. The tag is preserved (passed
explicitly) but **every other instance-level override is lost** — name, faction,
abilities, classes, feats, special abilities, equipment, natural AC, race,
conversation. So a placement that overrode any of those reverts to its blueprint
after the first death. (The headline symptom: Carn Dum City's "Numanan Numerocks
Second Hand", a renamed placement of `cultmember002`, respawns as the blueprint
name "Numarok The Black Hand".)

Fix
---
Give every diverging placement its own blueprint that already carries its
overrides, and repoint the placement's TemplateResRef at it. The tag is left
untouched (respawn re-applies it anyway), so no quest/script that looks up a tag
is affected.

What counts as "diverging" (respawn-losing identity):
    name (FirstName+LastName), FactionID, conversation, and the combat key
    (abilities, classes, feats, special abilities, equipment-by-resref, natural
    AC, race) — mirroring nwn-wiki's _creature_key plus name+faction+conv, which
    is exactly what module-index/creature_tag_conflicts.json and
    faction_bp_instance_discrepancies.json track.

Two sources of divergence are handled:
  * LOCAL base (a `<base>.utc.json` exists): a placement diverges if its identity
    differs from the blueprint's. Covered by the two reports.
  * STOCK base (no local .utc — a CEP/base-game blueprint): we cannot read the
    stock baseline, but if the same base is placed under >1 distinct identity we
    know at least all-but-one revert; we bake a dedicated blueprint for *every*
    distinct identity so all placements become deterministic. (These are the
    cases the reports miss, e.g. `nw_oldman` placed as "Mad Eye Moody",
    `old` as "Old Tagget"/"Ronus Holdorn".) A stock base placed under a single
    identity is left alone (no baseline to compare against).

Blueprints are baked from the placement's own GFF struct (which is a complete
creature), so the new blueprint reproduces the placement faithfully for *all*
fields, not just the identity ones.

Usage
-----
    python3 bin/split-divergent-creatures.py --dry-run     # plan only
    python3 bin/split-divergent-creatures.py               # apply
    python3 bin/split-divergent-creatures.py --manifest out.json

Idempotent: once placements point at their dedicated blueprints they are no
longer divergent, so re-running is a no-op.
"""

import argparse
import glob
import json
import os
import re
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
UNPACKED = os.path.join(ROOT, "unpacked")
MODULE_INDEX = os.path.join(ROOT, "module-index")

# GIT-instance-only fields that must be stripped to turn a placement struct into
# a blueprint (.utc) struct.
POSITIONAL = {"XPosition", "YPosition", "ZPosition",
              "XOrientation", "YOrientation", "__struct_id"}


# ---------------------------------------------------------------- GFF helpers
def fld(struct, key):
    v = struct.get(key) if isinstance(struct, dict) else None
    return v.get("value") if isinstance(v, dict) else None


def loc(v):
    """Resolve a cexolocstring's English (0) substring."""
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
    """Mirror nwn-wiki _creature_key(): combat identity, name/faction excluded."""
    abilities = tuple(fld(s, a) for a in ("Str", "Dex", "Con", "Int", "Wis", "Cha"))
    classes = tuple(sorted(
        (fld(cl, "Class"), fld(cl, "ClassLevel")) for cl in list_items(s, "ClassList")))
    feats = tuple(sorted(
        int(fld(f, "Feat")) for f in list_items(s, "FeatList") if fld(f, "Feat") is not None))
    spec = tuple(sorted(
        (fld(x, "Spell"), fld(x, "SpellCasterLevel")) for x in list_items(s, "SpecAbilityList")))
    # `__struct_id` is a bare int, not a {"type":..,"value":..} wrapper -- read it
    # directly; fld() only unwraps dicts and would drop the slot from the key.
    equip = tuple(sorted(
        (e.get("__struct_id"), (fld(e, "EquippedRes", ) or fld(e, "TemplateResRef") or ""))
        for e in list_items(s, "Equip_ItemList")))
    inventory = tuple(sorted(
        (fld(e, "InventoryRes") or fld(e, "TemplateResRef") or "")
        for e in list_items(s, "ItemList")))
    return (abilities, classes, feats, spec, equip, inventory,
            fld(s, "NaturalAC"), fld(s, "Race"))


def display_name(s):
    return ((loc(s.get("FirstName")) or "") + " " + (loc(s.get("LastName")) or "")).strip()


def identity_key(s):
    """Full respawn-losing identity: name + faction + conversation + combat."""
    return (display_name(s).lower(),
            fld(s, "FactionID"),
            (fld(s, "Conversation") or "").lower(),
            combat_key(s))


# ---------------------------------------------------------------- loading
_bp_cache = {}


def local_blueprint(resref):
    if resref not in _bp_cache:
        p = os.path.join(UNPACKED, f"{resref}.utc.json")
        _bp_cache[resref] = json.load(open(p, encoding="utf-8")) if os.path.exists(p) else None
    return _bp_cache[resref]


_STORE_RE = re.compile(r'SetLocalLocation\s*\([^;{}]*"spawn"')
_EXEC_RE = re.compile(r'ExecuteScript\s*\(\s*"([^"]+)"')
_storing_set = None


def spawn_storing_scripts():
    """Set of OnSpawn script resrefs that store a "spawn" leash home (resolving
    ExecuteScript chains). Mirrors tests/check_spawn_leash.py so baked blueprints
    stay compliant with the spawn-leash build gate."""
    global _storing_set
    if _storing_set is not None:
        return _storing_set
    direct, stores = {}, set()
    for path in glob.glob(os.path.join(UNPACKED, "*.nss")):
        resref = os.path.basename(path)[:-4].lower()
        try:
            text = open(path, encoding="utf-8", errors="replace").read()
        except OSError:
            continue
        if _STORE_RE.search(text):
            stores.add(resref)
        direct[resref] = {t.lower() for t in _EXEC_RE.findall(text)}
    changed = True
    while changed:
        changed = False
        for resref, targets in direct.items():
            if resref not in stores and targets & stores:
                stores.add(resref)
                changed = True
    _storing_set = stores
    return stores


def existing_resrefs():
    return {os.path.basename(p)[:-len(".utc.json")].lower()
            for p in glob.glob(os.path.join(UNPACKED, "*.utc.json"))}


def load_git_files():
    """area_resref -> (path, parsed_json, creature_list)."""
    out = {}
    for gf in sorted(glob.glob(os.path.join(UNPACKED, "*.git.json"))):
        area = os.path.basename(gf)[:-len(".git.json")]
        d = json.load(open(gf, encoding="utf-8"))
        cl = d.get("Creature List")
        if cl:
            out[area] = (gf, d, cl["value"])
    return out


# ---------------------------------------------------------------- planning
def plan(git):
    """Return (groups, stats).

    groups: list of dicts {base, identity, rep (area,idx), instances:[(area,idx)],
                           is_stock}
    """
    # base -> list of (area, idx, identity, struct)
    placements = {}
    for area, (_p, _d, clist) in git.items():
        for idx, c in enumerate(clist):
            base = fld(c, "TemplateResRef")
            if not base:
                continue
            placements.setdefault(base, []).append((area, idx, identity_key(c), c))

    groups = []
    for base, plist in sorted(placements.items()):
        bp = local_blueprint(base)
        # bucket placements by identity
        by_ident = {}
        for area, idx, ident, c in plist:
            by_ident.setdefault(ident, []).append((area, idx, c))
        if bp is not None:
            base_ident = identity_key(bp)
            for ident, members in by_ident.items():
                if ident != base_ident:
                    groups.append(_mk_group(base, ident, members, is_stock=False))
        else:
            # stock: only act when there is genuine ambiguity (>1 identity)
            if len(by_ident) > 1:
                for ident, members in by_ident.items():
                    groups.append(_mk_group(base, ident, members, is_stock=True))

    groups.sort(key=lambda g: (g["base"], g["rep"]))
    stats = {
        "groups": len(groups),
        "local_groups": sum(1 for g in groups if not g["is_stock"]),
        "stock_groups": sum(1 for g in groups if g["is_stock"]),
        "instances": sum(len(g["instances"]) for g in groups),
        "git_files": len({a for g in groups for a, _ in g["instances"]}),
    }
    return groups, stats


def _mk_group(base, ident, members, is_stock):
    members = sorted(members, key=lambda m: (m[0], m[1]))
    rep_area, rep_idx, rep_struct = members[0]
    return {
        "base": base,
        "identity": ident,
        "name": display_name(rep_struct) or "(unnamed)",
        "rep": (rep_area, rep_idx),
        "rep_struct": rep_struct,
        "instances": [(a, i) for a, i, _c in members],
        "is_stock": is_stock,
    }


def assign_resrefs(groups, taken):
    """Deterministic unique <=16-char resref per group. Mutates groups (adds
    'resref') and `taken`."""
    taken = {r.lower() for r in taken}
    for g in groups:
        base = g["base"]
        n = 2
        while True:
            suffix = f"_{n}"
            stem = base if len(base) + len(suffix) <= 16 else base[:16 - len(suffix)]
            cand = (stem + suffix).lower()
            if cand not in taken:
                break
            n += 1
        g["resref"] = cand
        taken.add(cand)


# ---------------------------------------------------------------- baking
def bake_blueprint(group):
    """Build a .utc blueprint struct from the representative placement struct."""
    import copy
    src = copy.deepcopy(group["rep_struct"])
    for k in POSITIONAL:
        src.pop(k, None)
    resref = group["resref"]
    # Preserve a PaletteID (toolset-only); inherit base's, else default.
    if "PaletteID" not in src:
        base_bp = local_blueprint(group["base"])
        src["PaletteID"] = (base_bp.get("PaletteID") if base_bp and "PaletteID" in base_bp
                            else {"type": "byte", "value": 44})
    src["TemplateResRef"] = {"type": "resref", "value": resref}
    # Keep the spawn-leash gate green: a placement whose OnSpawn doesn't store a
    # leash home was already un-leashed at runtime; mark the baked blueprint
    # NO_LEASH=1 so tests/check_spawn_leash.py accepts it (no behaviour change).
    if (fld(src, "ScriptSpawn") or "").strip().lower() not in spawn_storing_scripts():
        _ensure_no_leash(src)
    # .utc convention: __data_type first, remaining keys sorted.
    ordered = {"__data_type": "UTC "}
    for k in sorted(k for k in src if k != "__data_type"):
        ordered[k] = src[k]
    return ordered


def _ensure_no_leash(src):
    """Add local int NO_LEASH=1 to the struct's VarTable if not already present."""
    vt = src.get("VarTable")
    rows = vt.get("value") if isinstance(vt, dict) else None
    if not isinstance(rows, list):
        rows = []
        src["VarTable"] = {"type": "list", "value": rows}
    for row in rows:
        if isinstance(row, dict) and fld(row, "Name") == "NO_LEASH" and fld(row, "Value"):
            return
    rows.append({
        "__struct_id": 0,
        "Name": {"type": "cexostring", "value": "NO_LEASH"},
        "Type": {"type": "dword", "value": 1},
        "Value": {"type": "int", "value": 1},
    })


def write_json(path, obj):
    with open(path, "w", encoding="utf-8") as f:
        f.write(json.dumps(obj, indent=2, ensure_ascii=False))
        f.write("\n")


# ---------------------------------------------------------------- coverage
def coverage_warnings(groups, git):
    """Cross-check that every creature_tag_conflicts variant and every faction
    discrepancy instance is covered by some group. Returns list of warnings.

    A conflict base is only a genuine miss if it has a static (Creature-List)
    placement that actually diverges from its local blueprint in a respawn-losing
    field. The wiki's key also splits on encounter-pool copies and dialog-tree
    content, which are not SE-respawn problems — those are not flagged here."""
    warns = []
    covered_bases = {g["base"] for g in groups}
    covered_inst = {(a, i) for g in groups for a, i in g["instances"]}

    ctp = os.path.join(MODULE_INDEX, "creature_tag_conflicts.json")
    if os.path.exists(ctp):
        ct = json.load(open(ctp, encoding="utf-8"))
        miss = []
        for c in ct.get("conflicts", []):
            base = c["blueprint_resref"]
            if base in covered_bases:
                continue
            bp = local_blueprint(base)
            if bp is None:
                continue
            base_ident = identity_key(bp)
            for _area, (_p, _d, clist) in git.items():
                if any(fld(inst, "TemplateResRef") == base
                       and identity_key(inst) != base_ident for inst in clist):
                    miss.append(base)
                    break
        if miss:
            warns.append(f"creature_tag_conflicts bases with a real uncovered "
                         f"divergence: {sorted(miss)}")

    fdp = os.path.join(MODULE_INDEX, "faction_bp_instance_discrepancies.json")
    if os.path.exists(fdp):
        fd = json.load(open(fdp, encoding="utf-8"))
        miss = [(d["area_resref"], d["instance_index"]) for d in fd.get("discrepancies", [])
                if (d["area_resref"], d["instance_index"]) not in covered_inst]
        if miss:
            warns.append(f"faction discrepancy instances NOT covered: {sorted(miss)[:20]}"
                         f"{' …' if len(miss) > 20 else ''} ({len(miss)} total)")
    return warns


# ---------------------------------------------------------------- main
def main():
    ap = argparse.ArgumentParser(description=__doc__,
                                 formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--dry-run", action="store_true", help="plan only, write nothing")
    ap.add_argument("--manifest", metavar="PATH",
                    help="write a JSON manifest of created blueprints (for the test doc)")
    args = ap.parse_args()

    git = load_git_files()
    groups, stats = plan(git)
    assign_resrefs(groups, existing_resrefs())

    print(f"[split-divergent] {stats['groups']} dedicated blueprint(s) to create "
          f"({stats['local_groups']} local + {stats['stock_groups']} stock), "
          f"repointing {stats['instances']} placement(s) across {stats['git_files']} area(s).")
    for g in groups:
        a, i = g["rep"]
        tag = "stock" if g["is_stock"] else "local"
        print(f"  {g['base']:18s} -> {g['resref']:18s} [{tag}] "
              f"\"{g['name']}\" x{len(g['instances'])}  (e.g. {a}#{i})")

    for w in coverage_warnings(groups, git):
        print(f"  ! {w}", file=sys.stderr)

    manifest = {
        "blueprints": [
            {"base": g["base"], "resref": g["resref"], "name": g["name"],
             "is_stock": g["is_stock"],
             "areas": sorted({a for a, _ in g["instances"]}),
             "instances": [{"area": a, "index": i} for a, i in g["instances"]]}
            for g in groups
        ]
    }
    if args.manifest:
        write_json(args.manifest, manifest)
        print(f"[split-divergent] manifest -> {args.manifest}")

    if args.dry_run:
        print("[split-divergent] dry-run: no files written.")
        return 0

    # Apply: write blueprints, then repoint instances (one rewrite per git file).
    for g in groups:
        path = os.path.join(UNPACKED, f"{g['resref']}.utc.json")
        if not os.path.exists(path):
            write_json(path, bake_blueprint(g))

    dirty = {}
    for g in groups:
        for area, idx in g["instances"]:
            _p, d, clist = git[area]
            clist[idx]["TemplateResRef"]["value"] = g["resref"]
            dirty[area] = (_p, d)
    for area, (path, d) in dirty.items():
        write_json(path, d)

    print(f"[split-divergent] wrote {stats['groups']} blueprint(s), "
          f"updated {len(dirty)} area file(s).")
    return 0


if __name__ == "__main__":
    sys.exit(main())
