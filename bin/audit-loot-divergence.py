#!/usr/bin/env python3
"""Audit loot (droppability) divergence between creature blueprints and placements.

WHY THIS EXISTS
    se_respawn_inc.nss recreates a dead static creature from its BLUEPRINT,
    keeping only the tag. So a placed instance that disagrees with its blueprint
    silently reverts after that creature's first death. tests/check_divergent_
    creatures.py has gated that for identity, equipment and inventory since it
    was written -- but it compares equipment by slot and resref only, and
    deliberately ignored the `Dropable` flag. That is the flag that decides
    whether players get the item at all.

    The practical effect of a divergence here is loot that works exactly once
    per reboot: killable on the first pass, gone on every respawn after
    (blueprint says undroppable), or the reverse -- an item the blueprint
    intends players to have, which the placement withholds until the creature
    has died once. Found via `bilbobaggins`, whose placement dropped a
    crit-immunity armour its blueprint protects.

WHAT IT REPORTS
    Every (creature blueprint, placement, item) where the blueprint and the
    placed instance disagree on `Dropable`. Items that exist on one side and not
    the other are NOT reported here -- check_divergent_creatures.py already
    fails those.

    python3 bin/audit-loot-divergence.py                 # summary
    python3 bin/audit-loot-divergence.py --full          # every row
    python3 bin/audit-loot-divergence.py --markdown FILE # the decision document
    python3 bin/audit-loot-divergence.py --baseline FILE # the gate's known-list

WHICH SIDE IS RIGHT IS A JUDGEMENT CALL, WHICH IS WHY THIS IS A REPORT
    Nothing here is auto-fixable. `sting` on Bilbo reads as intended loot the
    blueprint forgot; a crit-immunity buff item on a boss reads as an instance
    someone hand-edited. Only a human can tell those apart, so the markdown
    carries a decision column and changes nothing.
"""

import argparse
import glob
import json
import os
import sys
from collections import defaultdict

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
UNPACKED = os.path.join(ROOT, "unpacked")

# The two item lists on a creature, and the field naming the item in each.
ITEM_LISTS = (
    ("Equip_ItemList", "equipped"),
    ("ItemList", "inventory"),
)


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


def display_name(s):
    return ((loc(s.get("FirstName")) or "") + " " + (loc(s.get("LastName")) or "")).strip()


def item_resref(entry):
    return (fld(entry, "EquippedRes") or fld(entry, "InventoryRes")
            or fld(entry, "TemplateResRef") or "")


def dropable(entry):
    """The flag, normalised. Absent means undroppable -- that is the toolset's
    own default and how the engine reads it."""
    return int(fld(entry, "Dropable") or 0)


def loot_map(struct):
    """(list, item resref) -> sorted tuple of Dropable flags.

    A tuple, not a single value, because a creature can carry several copies of
    the same item with different flags. Comparing multisets keeps that honest
    instead of letting the last one win.
    """
    out = defaultdict(list)
    for key, where in ITEM_LISTS:
        for entry in list_items(struct, key):
            resref = item_resref(entry)
            if resref:
                out[(where, resref)].append(dropable(entry))
    return {k: tuple(sorted(v)) for k, v in out.items()}


def blueprint(resref, cache):
    if resref not in cache:
        path = os.path.join(UNPACKED, f"{resref}.utc.json")
        try:
            cache[resref] = (json.load(open(path, encoding="utf-8"))
                             if os.path.exists(path) else None)
        except (OSError, json.JSONDecodeError):
            cache[resref] = None
    return cache[resref]


def scan():
    """Every blueprint/placement disagreement on Dropable."""
    cache = {}
    rows = []
    for gitfile in sorted(glob.glob(os.path.join(UNPACKED, "*.git.json"))):
        area = os.path.basename(gitfile)[: -len(".git.json")]
        try:
            data = json.load(open(gitfile, encoding="utf-8"))
        except (OSError, json.JSONDecodeError) as exc:
            print(f"warning: unreadable {area}.git.json: {exc}", file=sys.stderr)
            continue
        creatures = data.get("Creature List")
        if not creatures:
            continue

        for idx, placement in enumerate(creatures["value"]):
            base = fld(placement, "TemplateResRef")
            if not base:
                continue
            bp = blueprint(base, cache)
            if bp is None:
                # A stock/CEP blueprint: there is no local baseline to compare
                # against, so nothing provable. check_divergent_creatures.py
                # handles those by comparing placements against each other.
                continue

            bp_loot = loot_map(bp)
            inst_loot = loot_map(placement)
            for key, inst_flags in sorted(inst_loot.items()):
                bp_flags = bp_loot.get(key)
                if bp_flags is None or bp_flags == inst_flags:
                    continue
                where, resref = key
                rows.append({
                    "base": base,
                    "base_name": display_name(bp) or base,
                    "area": area,
                    "index": idx,
                    "placement_name": display_name(placement) or "",
                    "list": where,
                    "item": resref,
                    "blueprint": bp_flags,
                    "instance": inst_flags,
                })
    return rows


def direction(row):
    """Which way the divergence runs, in plain words."""
    bp_any = any(row["blueprint"])
    inst_any = any(row["instance"])
    if inst_any and not bp_any:
        return "instance drops, blueprint does not"
    if bp_any and not inst_any:
        return "blueprint drops, instance does not"
    return "counts differ"


def baseline_key(row):
    """A stable identity for the gate's known-list.

    Deliberately excludes the placement INDEX: reordering a Creature List is a
    routine toolset side effect and must not turn a known divergence into a new
    one. Two placements of the same blueprint in the same area diverging on the
    same item collapse to one entry, which is the right granularity for a
    decision that is taken per blueprint anyway.
    """
    return "|".join((row["base"], row["area"], row["list"], row["item"]))


def print_summary(rows):
    by_base = defaultdict(list)
    for row in rows:
        by_base[row["base"]].append(row)
    print(f"loot divergences (Dropable): {len(rows)} row(s) "
          f"across {len(by_base)} creature blueprint(s), "
          f"{len({baseline_key(r) for r in rows})} distinct blueprint/area/item case(s)")
    print()
    counts = defaultdict(int)
    for row in rows:
        counts[direction(row)] += 1
    for name, count in sorted(counts.items(), key=lambda kv: -kv[1]):
        print(f"  {count:5d}  {name}")
    print()
    print("worst-affected blueprints:")
    for base, group in sorted(by_base.items(), key=lambda kv: -len(kv[1]))[:15]:
        print(f"  {len(group):5d}  {base:24s} {group[0]['base_name']}")


def write_baseline(rows, path):
    """The known-list the gate reads: everything that exists today."""
    payload = {
        "_comment": [
            "Known blueprint/instance Dropable divergences, as measured when",
            "tests/check_divergent_creatures.py was tightened to cover loot.",
            "These are REPORTED but do not fail the build; anything NOT in this",
            "list does fail. Delete an entry once the underlying divergence is",
            "resolved -- the gate also complains about entries that no longer",
            "correspond to a real divergence, so this file cannot rot silently.",
            "Regenerate with: bin/audit-loot-divergence.py --baseline <this file>",
        ],
        "known": sorted({baseline_key(r) for r in rows}),
    }
    with open(path, "w", encoding="utf-8") as fh:
        json.dump(payload, fh, indent=2)
        fh.write("\n")
    print(f"wrote -> {path} ({len(payload['known'])} known case(s))")


def markdown(rows, path):
    by_base = defaultdict(list)
    for row in rows:
        by_base[row["base"]].append(row)

    lines = []
    add = lines.append
    add("<!-- GENERATED by bin/audit-loot-divergence.py. Re-run it rather than "
        "hand-editing the tables. -->")
    add("")
    add("# Loot divergence — blueprint vs. placement `Dropable`")
    add("")
    add("`se_respawn_inc.nss` recreates a dead static creature **from its "
        "blueprint**, keeping only the tag. So where a placement disagrees with "
        "its blueprint about whether an item is droppable, the loot works "
        "**exactly once per reboot** — as placed until that creature first "
        "dies, as the blueprint says forever after.")
    add("")
    add("`tests/check_divergent_creatures.py` now covers this, but every case "
        "below predates the change and is **reported, not gated** "
        "(`tests/known_loot_divergence.json`). New divergences fail the build.")
    add("")
    add("**Nothing here is auto-fixable and nothing has been changed.** Which "
        "side is right is a judgement call: `sting` on Bilbo reads as intended "
        "loot the blueprint forgot, while a buff item on a boss reads as a "
        "hand-edited placement. Fill in the **fix** column — `blueprint` (make "
        "the blueprint match the placement), `instance` (make the placement "
        "match the blueprint), or `leave`.")
    add("")
    add("## Summary")
    add("")
    add(f"- **{len(rows)}** diverging rows across **{len(by_base)}** creature "
        f"blueprints.")
    add(f"- **{len({baseline_key(r) for r in rows})}** distinct "
        "blueprint/area/item cases (the granularity the gate tracks).")
    counts = defaultdict(int)
    for row in rows:
        counts[direction(row)] += 1
    for name, count in sorted(counts.items(), key=lambda kv: -kv[1]):
        add(f"- **{count}** — {name}.")
    add("")
    add("Items that exist on one side and not the other are **not** listed "
        "here; `check_divergent_creatures.py` already failed the build on "
        "those.")
    add("")

    add("## By creature blueprint")
    add("")
    for base, group in sorted(by_base.items(), key=lambda kv: (-len(kv[1]), kv[0])):
        add(f"### `{base}` — {group[0]['base_name']} ({len(group)} row(s))")
        add("")
        add("| area | # | placement name | list | item | blueprint | instance "
            "| direction | fix |")
        add("|---|---:|---|---|---|---|---|---|---|")
        for row in sorted(group, key=lambda r: (r["area"], r["index"], r["item"])):
            bp_flags = ",".join(str(f) for f in row["blueprint"])
            inst_flags = ",".join(str(f) for f in row["instance"])
            add(f"| `{row['area']}` | {row['index']} | {row['placement_name']} "
                f"| {row['list']} | `{row['item']}` | {bp_flags} | {inst_flags} "
                f"| {direction(row)} |  |")
        add("")

    with open(path, "w", encoding="utf-8") as fh:
        fh.write("\n".join(lines) + "\n")
    print(f"wrote -> {path}")


def main():
    ap = argparse.ArgumentParser(
        description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--full", action="store_true", help="print every row")
    ap.add_argument("--markdown", metavar="FILE", help="write the decision document")
    ap.add_argument("--baseline", metavar="FILE",
                    help="write the gate's known-list")
    args = ap.parse_args()

    rows = scan()
    print_summary(rows)

    if args.full:
        print()
        for row in sorted(rows, key=lambda r: (r["base"], r["area"], r["index"])):
            print(f"  {row['base']:22s} {row['area']:20s} #{row['index']:<4d} "
                  f"{row['list']:9s} {row['item']:20s} "
                  f"bp={row['blueprint']} inst={row['instance']}")

    if args.markdown:
        markdown(rows, args.markdown)
    if args.baseline:
        write_baseline(rows, args.baseline)
    return 0


if __name__ == "__main__":
    sys.exit(main())
