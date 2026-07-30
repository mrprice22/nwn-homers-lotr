#!/usr/bin/env python3
"""Compensate the endgame roster for real character levels 41-60.

Real levels 41-60 (roadmap `ll-cls-progression`) handed every level-60 build
roughly **+10 attack bonus** while the world stayed at its season-1 numbers.
Creatures that already stood at 60+ class levels gained nothing, so the hardest
content quietly got easier. This script is the across-the-board numeric
correction.

Two independent halves, both keyed on the same qualification rule
(sum of ClassList[].ClassLevel >= 60):

  ability/AC half   roadmap `boss-ability-ac-bump`
      Str/Dex/Con/Int/Wis/Cha += 12 and NaturalAC += 10.
      ~+16 harder to hit, ~+6 to every save, more attack bonus and damage, and
      higher save DCs on the spells the creature itself casts.

  monk half         roadmap `boss-monk-sr-levels`   (skip with --no-monk)
      Every *existing* monk ClassList entry (Class 5, CLASS_TYPE_MONK) gains 15
      levels, raising Diamond Soul spell resistance back ahead of a level-60
      caster with Greater Spell Penetration. Never adds a monk entry to a
      creature that has none, so the 3-class engine limit is never touched.

The halves ship independently because the monk half carries a real unknown: the
stock class tables (cls_atk_2, cls_savthr_monk, cls_bfeat_monk) carry exactly 60
rows, so monk 61-75 runs off the end of them. It needs its own in-game UAT
before it goes anywhere near the tree. Use --no-monk until that UAT passes.

Usage:
    python3 bin/bump-legendary-npcs.py                    # dry run — both halves
    python3 bin/bump-legendary-npcs.py --no-monk          # dry run — ability/AC only
    python3 bin/bump-legendary-npcs.py --no-monk --apply  # write
    python3 bin/bump-legendary-npcs.py --diff             # dry run with unified diffs

LOCKSTEP IS MANDATORY. tests/check_divergent_creatures.py puts abilities,
ClassList and NaturalAC in its combat_key and `nwn-manager repack` aborts on a
mismatch between a blueprint and any of its static placements. Bumping only the
blueprint fails the build; bumping only the placement reverts on first death,
because se_respawn_inc.nss re-creates a dead static creature from the blueprint.
So every qualifying `.utc.json` **and** every qualifying `Creature List` entry in
every `.git.json` move together, in one pass. Encounter-spawned creatures need no
instance work — `Encounter List -> CreatureList` slots carry only a ResRef, so
their stats come from the blueprint.

IDEMPOTENCE is the contract: a second --apply must produce no diff. Each half
stamps its own VarTable marker (BOSS_BUMP_V / BOSS_MONK_V) on *both* sides and
skips any struct already carrying it. Two markers, not one: with a single shared
marker, shipping the ability half under --no-monk would permanently lock the monk
half out of the very creatures it targets. VarTable is not part of the divergence
gate's identity_key, so the markers are build-gate-neutral.

PLAYER SUMMONS ARE EXCLUDED (see PLAYER_SUMMONS below). Five qualifying
blueprints are creatures *players* summon rather than fight; bumping them would
work directly against the point of the exercise.

GFF helpers and the bake/write idioms are lifted from
bin/split-divergent-creatures.py; the load-mutate-write-only-if-changed shape is
bin/season-brand.py's.
"""
from __future__ import annotations

import argparse
import copy
import difflib
import glob
import json
import os
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
UNPACKED = os.path.join(ROOT, "unpacked")

ABILITIES = ("Str", "Dex", "Con", "Int", "Wis", "Cha")
ABILITY_BONUS = 12
NATURAL_AC_BONUS = 10
MONK_CLASS = 5          # CLASS_TYPE_MONK, hak_2da/classes.2da row 5
MONK_LEVELS = 15
LEGENDARY_LEVELS = 60   # total class levels that make a creature "endgame"
BYTE_MAX = 255

MARKER_BUMP = "BOSS_BUMP_V"
MARKER_MONK = "BOSS_MONK_V"
MARKER_VERSION = 1

# Creatures PLAYERS summon, not creatures players fight. They clear the >=60
# class-level bar, but bumping them hands the bonus to the player side and works
# against the whole point of this pass. The player-side lever is
# unpacked/summon_boost.nss, which already boosts summons at OnSpawn.
PLAYER_SUMMONS = {
    "epicdragonknight",   # Dragon Knight epic spell   -> x2_s2_dragknght.nss
    "mummyreaper",        # Mummy Dust epic spell      -> x2_s2_mumdust.nss
    "wwp_wizardslayer",   # summon monster line        -> nw_s0_summon.nss
    "petrock",            # Pet Rock summon            -> sum_petrock.nss
    "fellbeast_h",        # Horn of the Fell Beast     -> horn_summon.nss
}

# Qualifying placements whose TemplateResRef has no local .utc.json are placements
# of a stock CEP/base-game blueprint. Bumping such a placement alone is pointless:
# se_respawn_inc.nss rebuilds it from the stock blueprint and the bump is gone
# after the first death. So bake a local blueprint from the placement first, then
# bump both sides of that. Same trick bin/split-divergent-creatures.py uses.
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


def display_name(s):
    return ((loc(s.get("FirstName")) or "") + " " + (loc(s.get("LastName")) or "")).strip()


def total_class_levels(s):
    return sum(fld(cl, "ClassLevel") or 0 for cl in list_items(s, "ClassList"))


def qualifies(s):
    return total_class_levels(s) >= LEGENDARY_LEVELS


def dump_json(obj) -> str:
    """Match nwn_gff's JSON formatting exactly, so the diff shows only the fields
    this script changed and never a whole-file reformat."""
    return json.dumps(obj, indent=2, ensure_ascii=False) + "\n"


# ---------------------------------------------------------------- markers
def has_marker(s, name):
    for row in list_items(s, "VarTable"):
        if fld(row, "Name") == name and fld(row, "Value"):
            return True
    return False


def set_marker(s, name):
    """Append-or-update a VarTable int. Row shape matches _ensure_no_leash() in
    bin/split-divergent-creatures.py."""
    vt = s.get("VarTable")
    rows = vt.get("value") if isinstance(vt, dict) else None
    if not isinstance(rows, list):
        rows = []
        s["VarTable"] = {"type": "list", "value": rows}
    for row in rows:
        if isinstance(row, dict) and fld(row, "Name") == name:
            row["Value"] = {"type": "int", "value": MARKER_VERSION}
            return
    rows.append({
        "__struct_id": 0,
        "Name": {"type": "cexostring", "value": name},
        "Type": {"type": "dword", "value": 1},
        "Value": {"type": "int", "value": MARKER_VERSION},
    })


# ---------------------------------------------------------------- mutation
def bump_struct(s, do_monk, where, clamps):
    """Apply both halves to one creature struct in place.

    Returns a list of human-readable change notes (empty if nothing to do).
    `clamps` collects (where, field, wanted) for every value that hit the byte
    ceiling, so a silent truncation can never pass unreported.
    """
    notes = []

    if not has_marker(s, MARKER_BUMP):
        for a in ABILITIES:
            cur = fld(s, a)
            if cur is None:
                continue
            want = cur + ABILITY_BONUS
            new = min(want, BYTE_MAX)
            if new != want:
                clamps.append((where, a, want))
            s[a]["value"] = new
        cur_ac = fld(s, "NaturalAC")
        if cur_ac is None:
            # No blueprint in the tree lacks NaturalAC today, but a hand-authored
            # .utc could, and an absent field means 0.
            s["NaturalAC"] = {"type": "byte", "value": NATURAL_AC_BONUS}
            notes.append(f"NaturalAC (absent) -> {NATURAL_AC_BONUS}")
        else:
            want = cur_ac + NATURAL_AC_BONUS
            new = min(want, BYTE_MAX)
            if new != want:
                clamps.append((where, "NaturalAC", want))
            s["NaturalAC"]["value"] = new
            notes.append(f"NaturalAC {cur_ac} -> {new}")
        set_marker(s, MARKER_BUMP)
        notes.insert(0, f"abilities +{ABILITY_BONUS}")

    if do_monk and not has_marker(s, MARKER_MONK):
        touched = False
        for cl in list_items(s, "ClassList"):
            if fld(cl, "Class") == MONK_CLASS:
                cur = fld(cl, "ClassLevel") or 0
                cl["ClassLevel"]["value"] = cur + MONK_LEVELS
                notes.append(f"monk {cur} -> {cur + MONK_LEVELS}")
                touched = True
        if touched:
            # Only stamp the marker when there was a monk entry to grow. A
            # monk-less creature stays unstamped so it is re-evaluated if the
            # rule ever changes.
            set_marker(s, MARKER_MONK)

    return notes


# ---------------------------------------------------------------- loading
def load_blueprints():
    """resref -> (path, parsed json). Every local .utc.json in the tree."""
    out = {}
    for p in sorted(glob.glob(os.path.join(UNPACKED, "*.utc.json"))):
        resref = os.path.basename(p)[:-len(".utc.json")]
        out[resref] = (p, json.load(open(p, encoding="utf-8")))
    return out


def load_git_files():
    """area_resref -> (path, parsed json, creature list). Mirrors
    bin/split-divergent-creatures.py."""
    out = {}
    for gf in sorted(glob.glob(os.path.join(UNPACKED, "*.git.json"))):
        area = os.path.basename(gf)[:-len(".git.json")]
        d = json.load(open(gf, encoding="utf-8"))
        cl = d.get("Creature List")
        if cl:
            out[area] = (gf, d, cl["value"])
    return out


# ---------------------------------------------------------------- baking
def bake_resref(base, taken):
    """Deterministic unique <=16-char resref, matching assign_resrefs() in
    bin/split-divergent-creatures.py so the two scripts never collide."""
    n = 2
    while True:
        suffix = f"_{n}"
        stem = base if len(base) + len(suffix) <= 16 else base[:16 - len(suffix)]
        cand = (stem + suffix).lower()
        if cand not in taken:
            taken.add(cand)
            return cand
        n += 1


def bake_blueprint(inst_struct, resref):
    """Build a .utc blueprint struct from a placement struct. Same shape as
    bin/split-divergent-creatures.py's bake_blueprint(), minus the leash handling
    (we only ever bake a creature that is already placed and already leashed by
    whatever its OnSpawn does)."""
    src = copy.deepcopy(inst_struct)
    for k in POSITIONAL:
        src.pop(k, None)
    src["TemplateResRef"] = {"type": "resref", "value": resref}
    if "PaletteID" not in src:
        src["PaletteID"] = {"type": "byte", "value": 44}
    ordered = {"__data_type": "UTC "}
    for k in sorted(k for k in src if k != "__data_type"):
        ordered[k] = src[k]
    return ordered


# ---------------------------------------------------------------- planning
def plan(do_monk):
    """Compute every edit. Returns (edits, bakes, report).

    edits:  list of (path, old_text, new_text, [notes])
    bakes:  list of (path, text, base, resref, area, idx) for newly minted .utc
    report: dict of counters + the skip/clamp lists
    """
    blueprints = load_blueprints()
    git = load_git_files()
    taken = {r.lower() for r in blueprints}

    edits = []
    bakes = []
    clamps = []
    skipped_summons = []
    bumped_bps = []
    inst_count = 0
    monk_bps = 0

    # --- pass 1: stock-based qualifying placements need a local blueprint first.
    # Do this before the bump pass so the minted .utc and its repointed placement
    # both flow through the normal path below.
    stock_bakes = {}   # (area, idx) -> resref
    for area, (_p, _d, clist) in sorted(git.items()):
        for idx, c in enumerate(clist):
            base = fld(c, "TemplateResRef")
            if not base or base in blueprints or base in PLAYER_SUMMONS:
                continue
            if not qualifies(c):
                continue
            resref = bake_resref(base, taken)
            baked = bake_blueprint(c, resref)
            path = os.path.join(UNPACKED, f"{resref}.utc.json")
            stock_bakes[(area, idx)] = resref
            blueprints[resref] = (path, baked)
            bakes.append((path, baked, base, resref, area, idx))

    # --- pass 2: blueprints
    for resref, (path, obj) in sorted(blueprints.items()):
        if not qualifies(obj):
            continue
        if resref in PLAYER_SUMMONS:
            skipped_summons.append(resref)
            continue
        is_baked = any(b[3] == resref for b in bakes)
        old = None if is_baked else open(path, encoding="utf-8").read()
        notes = bump_struct(obj, do_monk, f"{resref}.utc", clamps)
        if not notes:
            continue
        bumped_bps.append(resref)
        if do_monk and any(n.startswith("monk ") for n in notes):
            monk_bps += 1
        if is_baked:
            continue     # written by the bake path, not as an edit
        new = dump_json(obj)
        if new != old:
            edits.append((path, old, new, [f'{display_name(obj) or resref}: ' + ", ".join(notes)]))

    # --- pass 3: placements, one write per area file
    for area, (path, doc, clist) in sorted(git.items()):
        old = open(path, encoding="utf-8").read()
        notes = []
        for idx, c in enumerate(clist):
            base = fld(c, "TemplateResRef")
            if not base:
                continue
            if (area, idx) in stock_bakes:
                base = stock_bakes[(area, idx)]
                c["TemplateResRef"]["value"] = base
                notes.append(f"#{idx} repointed at baked blueprint {base}")
            if base in PLAYER_SUMMONS or not qualifies(c):
                continue
            n = bump_struct(c, do_monk, f"{area}#{idx}", clamps)
            if n:
                inst_count += 1
                notes.append(f'#{idx} {display_name(c) or base}: ' + ", ".join(n))
        new = dump_json(doc)
        if new != old:
            edits.append((path, old, new, notes))

    report = {
        "blueprints": len(bumped_bps),
        "monk_blueprints": monk_bps,
        "instances": inst_count,
        "areas": sum(1 for p, _o, _n, _t in edits if p.endswith(".git.json")),
        "bakes": bakes,
        "clamps": clamps,
        "skipped_summons": sorted(skipped_summons),
    }
    return edits, bakes, report


# ---------------------------------------------------------------- main
def main() -> int:
    ap = argparse.ArgumentParser(description=__doc__,
                                 formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--apply", action="store_true", help="write the changes")
    ap.add_argument("--no-monk", action="store_true",
                    help="skip the +15 monk-level half (roadmap boss-monk-sr-levels), "
                         "which is still pending its in-game UAT")
    ap.add_argument("--diff", action="store_true", help="show full unified diffs")
    args = ap.parse_args()

    do_monk = not args.no_monk
    edits, bakes, rep = plan(do_monk)

    halves = "abilities/AC" + ("" if args.no_monk else " + monk levels")
    print(f"legendary NPC bump ({halves}); rule: total class levels >= {LEGENDARY_LEVELS}")
    print()

    if rep["skipped_summons"]:
        print(f"skipped (player-summonable, see PLAYER_SUMMONS): "
              f"{', '.join(rep['skipped_summons'])}")
        print()

    if not edits and not bakes:
        print("up to date — nothing to change")
        return 0

    for path, obj, base, resref, area, idx in bakes:
        print(f"{os.path.relpath(path, ROOT)}  (new)")
        print(f"    - baked from stock placement {area}#{idx} of {base} "
              f'— "{display_name(obj) or resref}"')

    for path, old, new, notes in edits:
        rel = os.path.relpath(path, ROOT)
        print(rel)
        for note in notes or ["(content changed)"]:
            print(f"    - {note}")
        if args.diff:
            for line in difflib.unified_diff(old.splitlines(True), new.splitlines(True),
                                             f"a/{rel}", f"b/{rel}"):
                print("    " + line.rstrip("\n"))
    print()

    if rep["clamps"]:
        print(f"!! {len(rep['clamps'])} value(s) CLAMPED at the byte ceiling "
              f"({BYTE_MAX}) — the full bonus did not land:", file=sys.stderr)
        for where, field, wanted in rep["clamps"]:
            print(f"     {where:<28} {field} wanted {wanted}", file=sys.stderr)
        print(file=sys.stderr)

    monk = f", {rep['monk_blueprints']} with monk levels" if do_monk else ""
    print(f"{rep['blueprints']} blueprint(s){monk}, {rep['instances']} placement(s) "
          f"across {rep['areas']} area file(s), {len(bakes)} blueprint(s) baked.")

    if not args.apply:
        print(f"{len(edits) + len(bakes)} file(s) would change. Re-run with --apply to "
              f"write (or --diff to see them).")
        return 0

    for path, obj, _base, _resref, _area, _idx in bakes:
        with open(path, "w", encoding="utf-8") as f:
            f.write(dump_json(obj))
    for path, _old, new, _notes in edits:
        with open(path, "w", encoding="utf-8") as f:
            f.write(new)

    print(f"wrote {len(edits) + len(bakes)} file(s).")
    if bakes:
        print("Next: `python3 bin/file-palette-orphans.py --apply` to file the new "
              "blueprint(s) — check_palette_coverage aborts the repack otherwise.")
    print("Then repack. A second --apply must produce no diff.")
    return 0


if __name__ == "__main__":
    sys.exit(main())
