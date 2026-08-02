#!/usr/bin/env python3
"""Resolve blueprint/placement `Dropable` divergences, ADDITIVELY.

The rule, decided by the admin 2026-08-02: **nothing loses loot.** Wherever a
creature blueprint and one of its placements disagree about whether an item is
droppable, both sides are set to droppable:

  * blueprint drops, placement does not  -> the PLACEMENT gains the flag
    ("give instances their missing blueprint items")
  * placement drops, blueprint does not  -> the BLUEPRINT gains the flag
    ("give blueprints their missing instance items")

Why it has to be both sides and not just one: se_respawn_inc.nss recreates a
dead static creature from its BLUEPRINT, keeping only the tag. Fixing only the
placement gives loot that disappears after the first death; fixing only the
blueprint gives loot that does not exist until then.

Items that exist on one side and not the other are NOT touched -- that is an
equipment/inventory divergence, which check_divergent_creatures.py fails
separately and which cannot be resolved by flipping a flag.

    python3 bin/fix-loot-divergence.py            # dry run (default)
    python3 bin/fix-loot-divergence.py --apply    # write the files

Idempotent: a second run finds nothing. Verify with
`python3 bin/audit-loot-divergence.py` (expect zero rows) and
`python3 tests/check_divergent_creatures.py`.

SAFETY: every file is round-tripped through json before it is written, and the
write is refused if re-serialising the UNCHANGED file would not reproduce it
byte for byte. That stops this script reformatting 300 lines of someone else's
blueprint as a side effect of setting one flag.
"""

import argparse
import collections
import glob
import json
import os
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
UNPACKED = os.path.join(ROOT, "unpacked")

ITEM_LISTS = (("Equip_ItemList", "equipped"), ("ItemList", "inventory"))


def fld(struct, key):
    v = struct.get(key) if isinstance(struct, dict) else None
    return v.get("value") if isinstance(v, dict) else None


def list_items(struct, key):
    v = struct.get(key)
    if isinstance(v, dict):
        v = v.get("value")
    return v if isinstance(v, list) else []


def item_resref(entry):
    return (fld(entry, "EquippedRes") or fld(entry, "InventoryRes")
            or fld(entry, "TemplateResRef") or "")


def flags_for(struct, where, item):
    """Sorted Dropable flags for one item in one of a creature's lists."""
    key = {"equipped": "Equip_ItemList", "inventory": "ItemList"}[where]
    return tuple(sorted(int(fld(e, "Dropable") or 0)
                        for e in list_items(struct, key)
                        if item_resref(e) == item))


def loot_map(struct):
    out = collections.defaultdict(list)
    for key, where in ITEM_LISTS:
        for entry in list_items(struct, key):
            resref = item_resref(entry)
            if resref:
                out[(where, resref)].append(int(fld(entry, "Dropable") or 0))
    return {k: tuple(sorted(v)) for k, v in out.items()}


def set_dropable(struct, where, item):
    """Force Dropable=1 on every copy of `item` in one list. Returns count."""
    key = {"equipped": "Equip_ItemList", "inventory": "ItemList"}[where]
    changed = 0
    entries = list_items(struct, key)
    for i, entry in enumerate(entries):
        if item_resref(entry) != item:
            continue
        existing = entry.get("Dropable")
        if isinstance(existing, dict):
            if existing.get("value") == 1:
                continue
            existing["value"] = 1
        else:
            # The key is absent entirely (the toolset omits it when the flag is
            # off). Insert it with the right GFF type, in the struct's own key
            # order: `__struct_id` FIRST, then alphabetical. Plain sorted()
            # gets this wrong -- '_' sorts after the uppercase letters, so it
            # would push __struct_id to the end of every struct it touched and
            # make a one-flag change look like a rewrite.
            entry["Dropable"] = {"type": "byte", "value": 1}
            entries[i] = collections.OrderedDict(
                sorted(entry.items(),
                       key=lambda kv: (kv[0] != "__struct_id", kv[0])))
        changed += 1
    return changed


class File:
    """A json file loaded once, edited in place, written only if it changed."""

    def __init__(self, path):
        self.path = path
        self.raw = open(path, encoding="utf-8").read()
        self.data = json.loads(self.raw,
                               object_pairs_hook=collections.OrderedDict)
        self.dirty = 0

    def serialise(self):
        return json.dumps(self.data, indent=2, ensure_ascii=False) + "\n"

    def round_trips(self):
        """True when re-serialising what we read reproduces the file exactly."""
        return json.dumps(json.loads(self.raw,
                                     object_pairs_hook=collections.OrderedDict),
                          indent=2, ensure_ascii=False) + "\n" == self.raw

    def write(self):
        open(self.path, "w", encoding="utf-8").write(self.serialise())


def main():
    ap = argparse.ArgumentParser(
        description=__doc__,
        formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--apply", action="store_true",
                    help="write the files (default is a dry run)")
    args = ap.parse_args()

    files = {}

    def load(path):
        if path not in files:
            files[path] = File(path)
        return files[path]

    actions = []   # (kind, where-desc, item, count)
    refused = []

    for gitpath in sorted(glob.glob(os.path.join(UNPACKED, "*.git.json"))):
        area = os.path.basename(gitpath)[: -len(".git.json")]
        gitfile = load(gitpath)
        creatures = gitfile.data.get("Creature List")
        if not creatures:
            continue

        for idx, placement in enumerate(creatures["value"]):
            base = fld(placement, "TemplateResRef")
            if not base:
                continue
            bppath = os.path.join(UNPACKED, f"{base}.utc.json")
            if not os.path.exists(bppath):
                continue          # stock/CEP blueprint: no local baseline
            bpfile = load(bppath)

            bp_loot = loot_map(bpfile.data)
            for key, inst_flags in sorted(loot_map(placement).items()):
                bp_flags = bp_loot.get(key)
                if bp_flags is None or bp_flags == inst_flags:
                    continue
                where, item = key

                # Additive: whichever side is not dropping, gains the flag.
                if any(bp_flags) and not all(inst_flags):
                    n = set_dropable(placement, where, item)
                    if n:
                        gitfile.dirty += n
                        actions.append(("placement", f"{area}#{idx}", item, n))
                if any(inst_flags) and not all(bp_flags):
                    n = set_dropable(bpfile.data, where, item)
                    if n:
                        bpfile.dirty += n
                        actions.append(("blueprint", base, item, n))
                        bp_loot = loot_map(bpfile.data)

    for path, f in sorted(files.items()):
        if not f.dirty:
            continue
        if not f.round_trips():
            refused.append(path)

    for kind, where, item, count in actions:
        copies = "" if count == 1 else f" x{count}"
        print(f"  {kind:9s} {where:24s} {item:22s} -> Dropable=1{copies}")

    dirty = {p: f for p, f in files.items() if f.dirty}
    print()
    print(f"{len(actions)} change(s) across {len(dirty)} file(s)")

    if refused:
        print("\nREFUSED -- these files would be reformatted by writing them, "
              "so nothing was written at all:", file=sys.stderr)
        for path in refused:
            print(f"  - {path}", file=sys.stderr)
        return 1

    if not args.apply:
        print("\nDry run. Nothing written. Re-run with --apply.")
        return 0

    for path, f in sorted(dirty.items()):
        f.write()
        print(f"wrote -> {os.path.relpath(path, ROOT)}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
