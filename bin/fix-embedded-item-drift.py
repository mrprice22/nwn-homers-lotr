#!/usr/bin/env python3
"""Resolve embedded-item drift rows from tests/embedded_item_drift.json.

Each row is one (creature blueprint, slot or inventory, item resref) whose
placed copies differ from <resref>.uti.json (see bin/audit-embedded-item-drift.py
for why that matters). A row is applied only when it has a `decision`:

  blueprint  overwrite every placed copy's content with the .uti's, keeping
             what belongs to the placement (Dropable, Pickpocketable, position,
             inventory grid, struct id). Only the first kill after a reboot
             changes -- it now matches every respawn.
  placed     the placed copy is the real item. Reuse a .uti whose content is
             identical to it if one exists, else MINT one (<resref>_<n>, the
             placed copy's content, the source's PaletteID). Point the creature
             blueprint's slot/inventory entry and every placement's copy at it,
             and resync any other placed variant of the pair to it. Every
             respawn then carries what the first kill did.

    python3 bin/fix-embedded-item-drift.py                       # dry run
    python3 bin/fix-embedded-item-drift.py --apply               # decided rows
    python3 bin/fix-embedded-item-drift.py --accept-recommended  # + undecided
                                                                 #   rows, by
                                                                 #   recommendation
    ... --class cosmetic          only rows of one class
    ... --only "<row key>"        one row (repeatable)

A row whose placed copies changed since the audit recorded them is refused:
re-run `bin/audit-embedded-item-drift.py --write` and decide it again.

After --apply:
    python3 bin/file-palette-orphans.py --apply   # file any minted blueprint
    python3 bin/audit-crit-immunity.py            # a mint must not bring crit immunity back
    python3 bin/audit-embedded-item-drift.py --write
    python3 tests/check_divergent_creatures.py

SAFETY: every file is round-tripped through json before it is written, and the
write is refused if re-serialising the UNCHANGED file would not reproduce it
byte for byte (the same guard as bin/fix-loot-divergence.py).
"""

import argparse
import collections
import copy
import datetime
import glob
import importlib.util
import json
import os
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
UNPACKED = os.path.join(ROOT, "unpacked")

_spec = importlib.util.spec_from_file_location(
    "audit_embedded_item_drift", os.path.join(ROOT, "bin", "audit-embedded-item-drift.py"))
A = importlib.util.module_from_spec(_spec)
_spec.loader.exec_module(A)

# Keys that belong to the placement, never to the item.
KEEP = A.INSTANCE_ONLY


def dumps(d):
    return json.dumps(d, indent=2, ensure_ascii=False) + "\n"


class Files:
    """Loads each file once, refuses ones that would not round-trip, writes changed ones."""

    def __init__(self):
        self.data, self.dirty, self.new = {}, set(), {}

    def get(self, path):
        if path not in self.data:
            raw = open(path, encoding="utf-8").read()
            d = json.loads(raw)
            if dumps(d) != raw:
                raise SystemExit(f"refusing: {os.path.relpath(path, ROOT)} does not "
                                 "round-trip byte-identically through json")
            self.data[path] = d
        return self.data[path]

    def touch(self, path):
        self.dirty.add(path)

    def create(self, path, d):
        self.new[path] = d

    def write(self):
        for path in sorted(self.dirty):
            open(path, "w", encoding="utf-8").write(dumps(self.data[path]))
        for path, d in sorted(self.new.items()):
            open(path, "w", encoding="utf-8").write(dumps(d))


def resync(placed, uti):
    """Placed copy -> the uti's content, keeping the placement's own keys.

    Existing keys keep their order; keys only the uti has go at the end.
    """
    out = {}
    for k, v in placed.items():
        if k in KEEP:
            out[k] = v
        elif k in uti and k not in A.UTI_ONLY:
            out[k] = copy.deepcopy(uti[k])
    for k, v in uti.items():
        if k not in out and k not in A.UTI_ONLY and k not in KEEP:
            out[k] = copy.deepcopy(v)
    placed.clear()
    placed.update(out)


def mint(resref, src_uti, cand, taken):
    n = 1
    while True:
        name = f"{resref[:16 - len(str(n)) - 1]}_{n}"
        if name not in taken and not os.path.exists(
                os.path.join(UNPACKED, f"{name}.uti.json")):
            break
        n += 1
    taken.add(name)
    new = {}
    for k in src_uti:
        if k in A.UTI_ONLY:
            new[k] = copy.deepcopy(src_uti[k])
        elif k in cand:
            new[k] = copy.deepcopy(cand[k])
    for k, v in cand.items():
        if k not in new and k not in KEEP:
            new[k] = copy.deepcopy(v)
    new["TemplateResRef"] = {"type": "resref", "value": name}
    new["Comment"] = {"type": "cexostring", "value": (
        f"Minted {datetime.date.today().isoformat()} by bin/fix-embedded-item-drift.py "
        f"from the copy embedded in placed {cand.get('_from', '')}; the {resref} "
        "blueprint is a different item.")}
    return name, new


def crit_immune(item):
    """ITEM_PROPERTY_IMMUNITY_MISCELLANEOUS (37) / IP_CONST_IMMUNITYMISC_CRITICAL_HITS (8)."""
    return any(A.fld(p, "PropertyName") == 37 and A.fld(p, "Subtype") == 8
               for p in A.fld(item, "PropertiesList") or [])


def matches(entry, where, resref, res_key):
    if A.fld(entry, res_key) != resref and A.fld(entry, "TemplateResRef") != resref:
        return False
    if where == "inventory":
        return True
    return entry.get("__struct_id") == int(where.split(":")[1])


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--apply", action="store_true", help="write the files")
    ap.add_argument("--accept-recommended", action="store_true",
                    help="treat an undecided row's recommendation as its decision")
    ap.add_argument("--class", dest="cls", choices=A.CLASS_ORDER,
                    help="only rows of this class")
    ap.add_argument("--only", action="append", default=[], help="only this row key")
    args = ap.parse_args()

    rows = A.load_decisions().get("pairs", {})
    live = A.scan()

    todo = []
    for key, r in sorted(rows.items()):
        if args.only and key not in args.only:
            continue
        if args.cls and r.get("class") != args.cls:
            continue
        dec = r.get("decision") or (r.get("recommend") if args.accept_recommended else None)
        if dec not in ("placed", "blueprint"):
            continue
        cur = live.get(key)
        if cur is None:
            print(f"skip {key}: no longer drifts (re-run the audit)")
            continue
        if (sorted(cur["variants"]) != r.get("placed_fps")
                or A.fingerprint(cur["_uti"]) != r.get("blueprint_fp")):
            print(f"REFUSE {key}: changed since the audit recorded it -- "
                  "re-run bin/audit-embedded-item-drift.py --write and decide again")
            continue
        todo.append((key, dec, r, cur))

    if not todo:
        print("nothing to do (no row has a decision"
              + ("" if args.accept_recommended else "; --accept-recommended uses the "
                 "recommendations") + ").")
        return 0

    files = Files()
    # Existing .uti files by content fingerprint, for `placed` reuse.
    uti_by_fp = {}
    for p in glob.glob(os.path.join(UNPACKED, "*.uti.json")):
        uti_by_fp.setdefault(A.fingerprint(json.load(open(p, encoding="utf-8"))),
                             os.path.basename(p)[:-len(".uti.json")])
    minted = {}         # candidate fp -> resref
    taken = set()
    git_paths = sorted(glob.glob(os.path.join(UNPACKED, "*.git.json")))
    summary = collections.Counter()

    for key, dec, r, cur in todo:
        cr, where, resref = r["creature"], r["where"], r["item"]
        lst, res_key = (("Equip_ItemList", "EquippedRes") if where != "inventory"
                        else ("ItemList", "InventoryRes"))
        if dec == "blueprint":
            target_res, target = resref, cur["_uti"]
            action = f"resync placed copies to {resref}.uti"
        else:
            cand = copy.deepcopy(cur["variants"][r["candidate_fp"]])
            fp = r["candidate_fp"]
            # The devcrit-roll pass stripped crit immunity from every blueprint
            # except the undead and the hand-picked *_ci items. Keeping a placed
            # copy must never bring it back where the blueprint dropped it.
            if crit_immune(cand) and not crit_immune(cur["_uti"]):
                print(f"REFUSE {key}: the placed copy is immune to critical hits and "
                      f"{resref}.uti is not (CLAUDE-devcrit-immunity-audit.md); "
                      "decide `blueprint`, or strip the property first")
                continue
            if fp in minted:
                target_res = minted[fp]
                action = f"repoint to {target_res} (minted above)"
            elif fp in uti_by_fp:
                target_res = uti_by_fp[fp]
                action = f"repoint to existing identical {target_res}.uti"
            else:
                cand["_from"] = cr
                target_res, new = mint(resref, cur["_uti"], cand, taken)
                files.create(os.path.join(UNPACKED, f"{target_res}.uti.json"), new)
                uti_by_fp[fp] = target_res
                summary["minted"] += 1
                action = (f"MINT {target_res}.uti from the placed "
                          f"{r['placed_name']!r} and repoint")
            minted[fp] = target_res
            path = os.path.join(UNPACKED, f"{target_res}.uti.json")
            target = files.new.get(path) or files.get(path)
        # The creature blueprint must NAME the item. A split blueprint
        # (bin/split-divergent-creatures.py) carries a full item struct here
        # instead; rewrite it in the toolset's canonical form either way, so
        # what a respawn gets no longer depends on how the engine reads one.
        upath = os.path.join(UNPACKED, f"{cr}.utc.json")
        if os.path.exists(upath):
            utc = files.get(upath)
            ents = A.fld(utc, lst) or []
            for i, e in enumerate(ents):
                if not matches(e, where, resref, res_key):
                    continue
                if res_key in e:
                    if e[res_key]["value"] != target_res:
                        e[res_key]["value"] = target_res
                        files.touch(upath)
                    continue
                canon = {"__struct_id": e.get("__struct_id")}
                for k in ("Dropable", "Pickpocketable"):
                    if k in e:
                        canon[k] = e[k]
                canon[res_key] = {"type": "resref", "value": target_res}
                for k in ("Repos_PosX", "Repos_Posy"):
                    if k in e:
                        canon[k] = e[k]
                ents[i] = canon
                files.touch(upath)
                summary["utc entries canonicalised"] += 1
        n = 0
        for gpath in git_paths:
            g = files.get(gpath)
            touched = False
            for c in A.fld(g, "Creature List") or []:
                if A.fld(c, "TemplateResRef") != cr:
                    continue
                for it in A.fld(c, lst) or []:
                    if not matches(it, where, resref, res_key):
                        continue
                    resync(it, target)
                    if "TemplateResRef" in it:
                        it["TemplateResRef"]["value"] = target_res
                    if res_key in it:
                        it[res_key]["value"] = target_res
                    n += 1
                    touched = True
            if touched:
                files.touch(gpath)
        summary[dec] += 1
        print(f"{dec:9} {key}: {action}; {n} placed copy(ies)")

    print(f"\n{summary['blueprint']} row(s) resynced to the blueprint, "
          f"{summary['placed']} kept as placed ({summary['minted']} new blueprint(s)); "
          f"{summary['utc entries canonicalised']} split-blueprint .utc entr(ies) "
          f"rewritten to name their item; "
          f"{len(files.dirty)} file(s) changed, {len(files.new)} created.")
    if not args.apply:
        print("Dry run. Nothing written. Re-run with --apply.")
        return 0
    files.write()
    print("Written. Next: bin/file-palette-orphans.py --apply, bin/audit-crit-immunity.py, "
          "bin/audit-embedded-item-drift.py --write, tests/check_divergent_creatures.py.")
    return 0


if __name__ == "__main__":
    sys.exit(main())
