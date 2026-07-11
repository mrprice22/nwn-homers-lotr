#!/usr/bin/env python3
"""Standardize area-transition map notes across the module.

Every area transition should carry a map-note pin on the area map telling the
player where it goes. This tool audits and (with --apply) creates those pins:

  * Doors / triggers / placeable "use" portals  -> a map note AT the transition
    object, labeled with the DESTINATION area's name.
  * Conversation ("talk") teleporters           -> ONE point-of-interest note at
    the teleporter NPC, labeled with the NPC's own name (not per-destination).

Transition resolution (which door goes where, edge kinds) is taken from
module-index/area_graph.json, the wiki's precomputed graph -- it already resolves
LinkedToFlags (door vs waypoint targets), duplicate tags, and script/dialog
teleports, so we don't re-implement that here. Object POSITIONS and NPC names
come from the raw unpacked/*.git.json / *.utc.json.

A map note is a WaypointList instance (__struct_id 5, resref nw_mapnote001) with
HasMapNote/MapNoteEnabled = 1 and MapNote = {"0": <text>}. Auto-created notes get
a deterministic Tag ("mnx_<objtag>" for transfers, "mnp_<npctag>" for NPC POIs)
so re-runs UPDATE the same note in place instead of duplicating -- the tool is
idempotent. Manual (hand-authored) notes already near a transition are left
alone (reported on mismatch; rewritten only with --update-manual).

.git and .gic are positional/parallel: every WaypointList entry appended to a
<area>.git.json gets a matching empty-comment struct appended to <area>.gic.json.

Default is a dry-run report; pass --apply to write.
"""
import argparse
import json
import math
import re
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
from boss_index import gv, locstr, ascii_fold, area_name, UNPACKED  # noqa: E402

ROOT = Path(__file__).resolve().parent.parent
GRAPH = ROOT / "module-index" / "area_graph.json"

MAPNOTE_RESREF = "nw_mapnote001"
XFER_PREFIX = "mnx_"          # transfer (destination) auto notes
POI_PREFIX = "mnp_"           # NPC point-of-interest auto notes
AUTO_PREFIXES = (XFER_PREFIX, POI_PREFIX)
MANUAL_RADIUS = 8.0           # a hand-placed note this close already covers it

# A .nss is a "teleport script" if it moves the speaker between locations.
JUMP_RE = re.compile(r"\b(?:Action)?Jump(?:ToLocation|ToObject)\b")


# --------------------------------------------------------------------------- #
# helpers
# --------------------------------------------------------------------------- #
def load(path):
    return json.loads(path.read_text(encoding="utf-8"))


def dump(path, data):
    path.write_text(json.dumps(data, indent=2, ensure_ascii=False) + "\n",
                    encoding="utf-8")


def by_tag(items, tag):
    """All structs in a *.git list whose Tag == tag."""
    return [it for it in items if gv(it.get("Tag")) == tag]


def door_pos(obj):
    return gv(obj.get("X")) or 0.0, gv(obj.get("Y")) or 0.0, gv(obj.get("Z")) or 0.0


def placeable_pos(obj):
    return gv(obj.get("X")) or 0.0, gv(obj.get("Y")) or 0.0, gv(obj.get("Z")) or 0.0


def trigger_pos(obj):
    """Trigger base position + centroid of its Geometry polygon (the base
    XPosition is a polygon corner, not the middle)."""
    bx, by = gv(obj.get("XPosition")) or 0.0, gv(obj.get("YPosition")) or 0.0
    geo = gv(obj.get("Geometry")) or []
    if geo:
        cx = sum(gv(p.get("PointX")) or 0.0 for p in geo) / len(geo)
        cy = sum(gv(p.get("PointY")) or 0.0 for p in geo) / len(geo)
        return bx + cx, by + cy, 0.01
    return bx, by, 0.01


def creature_pos(obj):
    return gv(obj.get("XPosition")) or 0.0, gv(obj.get("YPosition")) or 0.0, 0.01


def note_pos(w):
    return gv(w.get("XPosition")) or 0.0, gv(w.get("YPosition")) or 0.0


def is_auto(w):
    tag = gv(w.get("Tag")) or ""
    return tag.startswith(AUTO_PREFIXES)


def has_note(w):
    return gv(w.get("HasMapNote")) == 1 or bool(gv(w.get("MapNote")))


def note_text(w):
    return locstr(w.get("MapNote"))


def dist(ax, ay, bx, by):
    return math.hypot(ax - bx, ay - by)


def make_note(tag, text, x, y, z=0.01):
    return {
        "__struct_id": 5,
        "Appearance": {"type": "byte", "value": 1},
        "Description": {"type": "cexolocstring", "value": {}},
        "HasMapNote": {"type": "byte", "value": 1},
        "LinkedTo": {"type": "cexostring", "value": ""},
        "LocalizedName": {"type": "cexolocstring", "value": {"0": "Map Note"}},
        "MapNote": {"type": "cexolocstring", "value": {"0": text}},
        "MapNoteEnabled": {"type": "byte", "value": 1},
        "Tag": {"type": "cexostring", "value": tag},
        "TemplateResRef": {"type": "resref", "value": MAPNOTE_RESREF},
        "XOrientation": {"type": "float", "value": 0.0},
        "XPosition": {"type": "float", "value": round(x, 5)},
        "YOrientation": {"type": "float", "value": 1.0},
        "YPosition": {"type": "float", "value": round(y, 5)},
        "ZPosition": {"type": "float", "value": round(z, 5) or 0.01},
    }


def gic_comment():
    return {"__struct_id": 5, "Comment": {"type": "cexostring", "value": ""}}


def sanitize_tag(prefix, base):
    base = re.sub(r"[^0-9A-Za-z_]", "", base)[:56]
    return prefix + base


# --------------------------------------------------------------------------- #
# core
# --------------------------------------------------------------------------- #
class AreaEditor:
    """Buffers note additions/updates for one area's .git + .gic pair."""

    def __init__(self, resref):
        self.resref = resref
        self.git_path = UNPACKED / f"{resref}.git.json"
        self.gic_path = UNPACKED / f"{resref}.gic.json"
        self.git = load(self.git_path)
        self.gic = load(self.gic_path)
        self.wl = gv(self.git.setdefault(
            "WaypointList", {"type": "list", "value": []}))
        self.gwl = gv(self.gic.setdefault(
            "WaypointList", {"type": "list", "value": []}))
        self.dirty = False
        self.desync = len(self.wl) != len(self.gwl)
        # index existing auto notes by their deterministic tag
        self.auto = {gv(w.get("Tag")): w for w in self.wl if is_auto(w)}
        self.manual = [w for w in self.wl if has_note(w) and not is_auto(w)]

    def manual_cover(self, x, y):
        for w in self.manual:
            mx, my = note_pos(w)
            if dist(x, y, mx, my) <= MANUAL_RADIUS:
                return w
        return None

    def upsert(self, tag, text, x, y, z, update_manual):
        """Returns one of: 'added', 'updated', 'manual-skip', 'manual-fix',
        'unchanged', 'manual-mismatch'."""
        cur = self.auto.get(tag)
        if cur is not None:
            # compare at the same precision we store (round-5), else float
            # re-rounding of a re-derived centroid reports a phantom change
            changed = (note_text(cur) != text
                       or gv(cur.get("XPosition")) != round(x, 5)
                       or gv(cur.get("YPosition")) != round(y, 5))
            if changed:
                cur["MapNote"]["value"] = {"0": text}
                cur["XPosition"]["value"] = round(x, 5)
                cur["YPosition"]["value"] = round(y, 5)
                self.dirty = True
                return "updated"
            return "unchanged"
        man = self.manual_cover(x, y)
        if man is not None:
            if note_text(man) == text:
                return "manual-skip"
            if update_manual:
                man["MapNote"]["value"] = {"0": text}
                if gv(man.get("HasMapNote")) != 1:
                    man["HasMapNote"]["value"] = 1
                if gv(man.get("MapNoteEnabled")) != 1:
                    man.setdefault("MapNoteEnabled",
                                   {"type": "byte", "value": 1})["value"] = 1
                self.dirty = True
                return "manual-fix"
            return "manual-mismatch"
        note = make_note(tag, text, x, y, z)
        self.wl.append(note)
        self.gwl.append(gic_comment())
        self.auto[tag] = note
        self.dirty = True
        return "added"

    def save(self):
        if self.dirty:
            dump(self.git_path, self.git)
            dump(self.gic_path, self.gic)


def teleport_scripts():
    out = set()
    for nss in UNPACKED.glob("*.nss"):
        try:
            if JUMP_RE.search(nss.read_text(encoding="utf-8", errors="ignore")):
                out.add(nss.stem)
        except OSError:
            pass
    return out


def dlg_scripts(conv):
    p = UNPACKED / f"{conv}.dlg.json"
    if not p.exists():
        return set()
    d = load(p)
    out = set()
    for key in ("EntryList", "ReplyList"):
        for n in gv(d.get(key)) or []:
            s = gv(n.get("Script"))
            if s:
                out.add(s)
    return out


def creature_name(c):
    name = locstr(c.get("FirstName")).strip()
    last = locstr(c.get("LastName")).strip()
    if name and last:
        name = f"{name} {last}"
    if not name:
        bp = UNPACKED / f"{gv(c.get('TemplateResRef'))}.utc.json"
        if bp.exists():
            d = load(bp)
            name = (locstr(d.get("FirstName")) + " "
                    + locstr(d.get("LastName"))).strip()
    return name or gv(c.get("Tag")) or "NPC"


# --------------------------------------------------------------------------- #
# main
# --------------------------------------------------------------------------- #
def main():
    ap = argparse.ArgumentParser(description=__doc__,
                                 formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--apply", action="store_true",
                    help="write .git/.gic edits (default: dry-run report)")
    ap.add_argument("--update-manual", action="store_true",
                    help="also rewrite hand-placed notes whose text disagrees")
    ap.add_argument("--verbose", action="store_true",
                    help="list every note action, not just the summary")
    args = ap.parse_args()

    if not GRAPH.exists():
        sys.exit(f"missing {GRAPH} -- run the wiki once to build module-index/")
    graph = load(GRAPH)["areas"]

    tele = teleport_scripts()
    editors = {}

    def ed(resref):
        if resref not in editors:
            editors[resref] = AreaEditor(resref)
        return editors[resref]

    stats = {k: 0 for k in ("added", "updated", "unchanged", "manual-skip",
                            "manual-fix", "manual-mismatch")}
    missing_src = []       # (area, kind, label, to_name) object not found
    dup_tag = []           # (area, kind, label) multiple source objects
    mismatches = []        # (area, tag, old, new)
    log = []

    KIND_LIST = {"door": "Door List", "trigger": "TriggerList",
                 "use": "Placeable List"}
    KIND_POS = {"door": door_pos, "trigger": trigger_pos, "use": placeable_pos}

    # ---- Pass A: door / trigger / use -> destination note --------------- #
    for area in sorted(graph):
        info = graph[area]
        edges = [t for t in info.get("transitions", [])
                 if t["kind"] in KIND_LIST]
        if not edges:
            continue
        e = ed(area)
        git_items = {k: gv(e.git.get(v)) or [] for k, v in KIND_LIST.items()}
        # group edges by (kind, label); an object whose tag serves several
        # distinct destinations is ambiguous (e.g. the Gwathdor maze / Well of
        # Eru "AreaTransition" triggers) -- we can't tell which pin means what,
        # so skip it rather than mislabel.
        groups = {}
        for t in edges:
            groups.setdefault((t["kind"], t.get("label") or ""), set()).add(
                t.get("to_name") or t.get("to") or "?")
        for (kind, label), dests in sorted(groups.items()):
            objs = by_tag(git_items[kind], label)
            if not objs:
                for d in dests:
                    missing_src.append((area, kind, label, d))
                continue
            if len(dests) > 1:
                dup_tag.append((area, kind, label, "multi-dest", sorted(dests)))
                continue
            dest = next(iter(dests))
            # one note per source object (same-tag doors sit at different spots)
            for i, obj in enumerate(objs):
                x, y, z = KIND_POS[kind](obj)
                suffix = label if len(objs) == 1 else f"{label}_{i}"
                tag = sanitize_tag(XFER_PREFIX, suffix)
                r = e.upsert(tag, dest, x, y, z, args.update_manual)
                stats[r] += 1
                if r == "manual-mismatch":
                    mismatches.append((area, label, dest))
                log.append((area, "xfer", kind, label, dest, r))

    # ---- Pass B: talk teleporter NPCs -> one POI note each -------------- #
    talk_areas = sorted({a for a, info in graph.items()
                         if any(t["kind"] == "talk"
                                for t in info.get("transitions", []))})
    for area in talk_areas:
        e = ed(area)
        creatures = gv(e.git.get("Creature List")) or []
        placed = set()
        for c in creatures:
            conv = gv(c.get("Conversation"))
            if not conv or not (dlg_scripts(conv) & tele):
                continue
            name = creature_name(c)
            if name in placed:
                continue
            placed.add(name)
            x, y, z = creature_pos(c)
            tag = sanitize_tag(POI_PREFIX, gv(c.get("Tag")) or name)
            r = e.upsert(tag, name, x, y, z, args.update_manual)
            stats[r] += 1
            log.append((area, "poi", "talk", gv(c.get("Tag")), name, r))

    # ---- report -------------------------------------------------------- #
    if args.verbose:
        for area, cls, kind, label, text, r in log:
            print(f"  [{r:14}] {area:22} {cls} {kind:7} {label!r:24} -> {text!r}")
        print()

    print("=== gen-map-notes summary "
          f"({'APPLY' if args.apply else 'DRY-RUN'}) ===")
    for k in ("added", "updated", "unchanged", "manual-skip", "manual-fix",
              "manual-mismatch"):
        print(f"  {k:16} {stats[k]}")
    print(f"  areas touched     {sum(1 for e in editors.values() if e.dirty)}")

    if missing_src:
        print(f"\n-- transitions with no source object in the area "
              f"({len(missing_src)}) [dead/renamed link; no note added]:")
        for area, kind, label, dest in missing_src[:40]:
            print(f"     {area:22} {kind:7} {label!r:24} -> {dest!r}")
        if len(missing_src) > 40:
            print(f"     ... and {len(missing_src) - 40} more")
    if dup_tag:
        print(f"\n-- ambiguous source tags ({len(dup_tag)}) "
              f"[one tag -> several destinations; skipped, no note]:")
        for area, kind, label, _why, dests in dup_tag:
            print(f"     {area:22} {kind:7} {label!r:18} -> {dests}")
    if mismatches:
        print(f"\n-- manual notes disagreeing with destination "
              f"({len(mismatches)}) [left as-is; use --update-manual]:")
        for area, label, dest in mismatches:
            print(f"     {area:22} {label!r:24} should read {dest!r}")

    desynced = [e.resref for e in editors.values() if e.desync]
    if desynced:
        print(f"\n-- WARNING: pre-existing .git/.gic WaypointList length mismatch "
              f"in: {', '.join(desynced)}")
        print("   (appended notes keep counts balanced; the prior offset is "
              "untouched)")

    if args.apply:
        for e in editors.values():
            e.save()
        print("\nwrote changes.")
    else:
        print("\n(dry-run -- pass --apply to write)")


if __name__ == "__main__":
    main()
