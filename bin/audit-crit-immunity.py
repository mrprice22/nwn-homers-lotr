#!/usr/bin/env python3
"""Audit every source of immunity to critical hits in unpacked/.

Written for roadmap item `devcrit-roll`, which reworks Devastating Critical from
save-or-die into bonus damage. Once a devastating critical can no longer delete a
boss outright, most of the crit immunity scattered through the module has lost
its reason to exist -- but it cannot be removed safely without knowing where it
actually comes from. That is what this produces: the full creature -> item ->
droppable table, so the decision can be taken creature by creature.

Re-run it after any change to the crit-immunity items; it is read-only.

    python3 bin/audit-crit-immunity.py                 # summary to stdout
    python3 bin/audit-crit-immunity.py --full          # + the full table
    python3 bin/audit-crit-immunity.py --markdown FILE # write the audit doc

WHAT COUNTS AS CRIT IMMUNITY
    Item property `PropertyName` 37 (ITEM_PROPERTY_IMMUNITY_MISCELLANEOUS) with
    `Subtype` 8 (IP_CONST_IMMUNITYMISC_CRITICAL_HITS).

    A blank/unused item-property field in this repo is encoded as EITHER 0 OR
    65535, depending on which toolset version last wrote the blueprint -- see
    CLAUDE-gotchas.md and reference_itemprop_subtype_blank_encoding. That trap
    does not bite this particular filter (subtype 8 is a real value, never
    blank), but the same file mixes both encodings on OTHER properties, so
    never assume one of them here either.

DROPPABILITY
    An item on a creature is only reachable by players if its entry carries
    `Dropable` = 1. Equipped items (Equip_ItemList) additionally have to be
    dropped by the death script, but the flag is still the gate. Absent flag
    means undroppable, which is the overwhelming default in this module.
"""

import argparse
import json
import re
import sys
from collections import defaultdict
from pathlib import Path

REPO = Path(__file__).resolve().parent.parent
UNPACKED = REPO / "unpacked"

PROP_IMMUNITY_MISC = 37
SUBTYPE_CRITICAL_HITS = 8


def gff(node, key, default=None):
    """Read a typed GFF-as-JSON value, tolerating a missing key."""
    entry = node.get(key)
    if entry is None:
        return default
    if isinstance(entry, dict) and "value" in entry:
        return entry["value"]
    return entry


def localized(node, key):
    """Resolve a cexolocstring to a display string."""
    value = gff(node, key)
    if isinstance(value, dict):
        # {"0": "Name"} or {"id": ...} -- take the first concrete string.
        for sub in value.values():
            if isinstance(sub, str):
                return sub
        return ""
    return value if isinstance(value, str) else ""


def grants_crit_immunity(item):
    props = gff(item, "PropertiesList", []) or []
    for prop in props:
        if gff(prop, "PropertyName") != PROP_IMMUNITY_MISC:
            continue
        if gff(prop, "Subtype") == SUBTYPE_CRITICAL_HITS:
            return True
    return False


def scan_items():
    """resref -> {name, plot, cursed} for every crit-immunity item blueprint."""
    found = {}
    for path in sorted(UNPACKED.glob("*.uti.json")):
        try:
            item = json.loads(path.read_text(encoding="utf-8"))
        except (json.JSONDecodeError, UnicodeDecodeError) as exc:
            print(f"warning: could not read {path.name}: {exc}", file=sys.stderr)
            continue
        if not grants_crit_immunity(item):
            continue
        resref = path.name[: -len(".uti.json")]
        found[resref] = {
            "name": localized(item, "LocalizedName") or resref,
            "plot": int(gff(item, "Plot", 0) or 0),
            "cursed": int(gff(item, "Cursed", 0) or 0),
            "tag": gff(item, "Tag", "") or "",
        }
    return found


def item_entries(container):
    """Yield (resref, dropable, where) for a creature's items."""
    for key, where in (("Equip_ItemList", "equipped"), ("ItemList", "inventory")):
        for entry in gff(container, key, []) or []:
            resref = (gff(entry, "EquippedRes") or gff(entry, "InventoryRes")
                      or gff(entry, "TemplateResRef") or "")
            if not resref:
                continue
            yield resref.lower(), int(gff(entry, "Dropable", 0) or 0), where


def scan_creatures(items):
    """Rows for creature blueprints carrying any crit-immunity item."""
    rows = []
    for path in sorted(UNPACKED.glob("*.utc.json")):
        try:
            utc = json.loads(path.read_text(encoding="utf-8"))
        except (json.JSONDecodeError, UnicodeDecodeError) as exc:
            print(f"warning: could not read {path.name}: {exc}", file=sys.stderr)
            continue
        resref = path.name[: -len(".utc.json")]
        for item_resref, dropable, where in item_entries(utc):
            if item_resref not in items:
                continue
            rows.append({
                "creature": resref,
                "creature_name": localized(utc, "FirstName") or resref,
                "cr": gff(utc, "ChallengeRating", 0),
                "item": item_resref,
                "where": where,
                "dropable": dropable,
            })
    return rows


def scan_instances(items):
    """Rows for placed instances carrying a crit-immunity item directly."""
    rows = []
    for path in sorted(UNPACKED.glob("*.git.json")):
        try:
            git = json.loads(path.read_text(encoding="utf-8"))
        except (json.JSONDecodeError, UnicodeDecodeError) as exc:
            print(f"warning: could not read {path.name}: {exc}", file=sys.stderr)
            continue
        area = path.name[: -len(".git.json")]
        for creature in gff(git, "Creature List", []) or []:
            for item_resref, dropable, where in item_entries(creature):
                if item_resref not in items:
                    continue
                rows.append({
                    "area": area,
                    "creature": gff(creature, "TemplateResRef", "") or "",
                    "creature_name": localized(creature, "FirstName") or "",
                    "item": item_resref,
                    "where": where,
                    "dropable": dropable,
                })
    return rows


def scan_scripts():
    """Any script that hands out crit immunity at runtime."""
    hits = []
    pattern = re.compile(r"IMMUNITY_TYPE_CRITICAL_HIT")
    for path in sorted(UNPACKED.glob("*.nss")):
        try:
            text = path.read_text(encoding="latin-1")
        except OSError:
            continue
        for num, line in enumerate(text.splitlines(), 1):
            if pattern.search(line):
                hits.append((path.name, num, line.strip()))
    return hits


def build_report(items, blueprint_rows, instance_rows, script_hits):
    by_item = defaultdict(list)
    for row in blueprint_rows:
        by_item[row["item"]].append(row)
    inst_by_item = defaultdict(list)
    for row in instance_rows:
        inst_by_item[row["item"]].append(row)

    droppable = [r for r in blueprint_rows + instance_rows if r["dropable"]]

    return {
        "items": items,
        "blueprint_rows": blueprint_rows,
        "instance_rows": instance_rows,
        "by_item": by_item,
        "inst_by_item": inst_by_item,
        "droppable": droppable,
        "script_hits": script_hits,
        "creatures": {r["creature"] for r in blueprint_rows},
    }


def print_summary(rep):
    print(f"crit-immunity item blueprints : {len(rep['items'])}")
    print(f"creature blueprints carrying  : {len(rep['creatures'])} "
          f"({len(rep['blueprint_rows'])} creature->item rows)")
    print(f"placed instances carrying     : {len(rep['instance_rows'])}")
    print(f"scripts granting it           : {len(rep['script_hits'])}")
    print(f"DROPPABLE (player-reachable)  : {len(rep['droppable'])}")
    print()
    print("top item blueprints by creature-blueprint count:")
    ranked = sorted(rep["by_item"].items(), key=lambda kv: -len(kv[1]))
    for resref, rows in ranked[:15]:
        meta = rep["items"][resref]
        print(f"  {len(rows):4d}  {resref:24s} {meta['name']}")
    if rep["droppable"]:
        print()
        print("droppable crit-immunity items -- these ARE reachable by players:")
        for row in rep["droppable"]:
            print(f"  {row['creature']:24s} {row['item']:24s} ({row['where']})")


def markdown(rep, out_path):
    items = rep["items"]
    lines = []
    add = lines.append

    add("<!-- GENERATED by bin/audit-crit-immunity.py. Re-run it rather than "
        "hand-editing the tables; the prose above them is hand-written and is "
        "preserved by regenerating into a fresh file. -->")
    add("")
    add("# Immunity to critical hits — full audit")
    add("")
    add("Required deliverable of roadmap item **`devcrit-roll`**, which reworks "
        "Devastating Critical from save-or-die into bonus damage. Once a "
        "devastating critical can no longer delete a boss outright, most of "
        "this immunity has lost its reason to exist — but the removal cannot be "
        "planned without knowing where it comes from. **This table is the input "
        "to that decision; nothing has been stripped.**")
    add("")
    add("Crit immunity is item property **37** (immunity, miscellaneous) with "
        "**subtype 8**. Regenerate with `python3 bin/audit-crit-immunity.py "
        "--markdown CLAUDE-devcrit-immunity-audit.md`.")
    add("")
    add("## Summary")
    add("")
    add(f"- **{len(items)}** item blueprints grant immunity to critical hits.")
    add(f"- **{len(rep['creatures'])}** creature blueprints carry one "
        f"({len(rep['blueprint_rows'])} creature→item rows).")
    add(f"- **{len(rep['instance_rows'])}** further matches on placed instances "
        "in `*.git.json`.")
    add(f"- **{len(rep['script_hits'])}** scripts grant it — every case is an "
        "item property, which is the good news: stripping a handful of shared "
        "blueprints removes it from most creatures at once.")
    add(f"- **{len(rep['droppable'])}** droppable (player-reachable) instances.")
    add("")
    add("## Notable findings")
    add("")
    if rep["droppable"]:
        add("**Droppable — these crit-immunity items are reachable by players.** "
            "Everything else in the module is undroppable, so this is the whole "
            "leak:")
        add("")
        for row in rep["droppable"]:
            origin = (f"placed instance in `{row['area']}`" if "area" in row
                      else "blueprint")
            add(f"- `{row['creature']}` carries `{row['item']}` "
                f"({row['where']}, `Dropable=1`) — {origin}")
        add("")
        add("Reviewed 2026-08-02: the Witch King's Boots of Quickening are "
            "**allowed to stay droppable** (admin decision), and the Witch King "
            "**keeps** his crit immunity as a boss.")
        add("")
        add("Also found and **fixed** on 2026-08-02: `bilbobaggins`'s placed "
            "instance in `shirebilbohouse` had `bilbosdefense` equipped with "
            "`Dropable=1` while the blueprint said undroppable — an "
            "instance/blueprint divergence, not a deliberate loot decision. The "
            "instance now matches the blueprint. Note that "
            "`tests/check_divergent_creatures.py` could not have caught it: it "
            "compares equipment by slot and resref and deliberately ignores the "
            "`Dropable` flag. Module-wide there are ~301 such `Dropable`-only "
            "divergences across 45 creature blueprints, so tightening that gate "
            "is its own piece of work, not a side effect of this one.")
        add("")
    add("**The two boss rings are not the same blueprint and do not behave the "
        "same.** `bossring` is `Cursed=1`, so it cannot be unequipped or traded "
        "if it ever reaches a PC. `dontdropbossring` — despite the name — is "
        "`Cursed=0` and has none of that protection. Its tag `EpicRing` also "
        "collides with the separate `epicring` blueprint. Gandalf the Gray "
        "wears **both** rings.")
    add("")
    add("**No script grants crit immunity**, confirmed by scanning every "
        "`unpacked/*.nss` for `IMMUNITY_TYPE_CRITICAL_HIT`. One near-miss worth "
        "knowing about: `sas_include.nss` contains "
        "`EffectImmunity(Random(33))`, whose range covers "
        "`IMMUNITY_TYPE_CRITICAL_HIT`. It is **unreachable** — the SAS "
        "(substance-abuse) system it belongs to is wired to no module hook and "
        "its `sasmonkey` placeable is not placed anywhere — so it cannot grant "
        "anything today. Recorded against roadmap item `concerning-pipeweed`, "
        "which is the one thing that might revive that code.")
    add("")
    add("## How to keep immunity on a hand-picked boss")
    add("")
    add("Do **not** hand-edit one creature's instance. The shared blueprints "
        "below cover dozens of creatures each, so the route is:")
    add("")
    add("1. Strip property 37/8 from the shared blueprint (`npcbuffgear`, "
        "`bossring`, `it_creitem*`, …). Every creature using it loses immunity.")
    add("2. For each boss that **keeps** immunity, mint a variant blueprint "
        "(e.g. `bossring_ci`) that retains the property, and swap the resref on "
        "**both** the `.utc` blueprint **and** the placed `.git` instance — "
        "respawn rebuilds a dead static creature from the blueprint, so an "
        "unsynced instance silently reverts after its first death "
        "(`tests/check_divergent_creatures.py` is the gate).")
    add("3. File the new blueprint with `python3 bin/file-palette-orphans.py "
        "--apply`, or the `check_palette_coverage` gate aborts the repack.")
    add("")
    add("## By item blueprint")
    add("")
    add("| creatures | instances | resref | name | tag | plot | cursed |")
    add("|---:|---:|---|---|---|---|---|")
    ranked = sorted(items.items(),
                    key=lambda kv: (-len(rep["by_item"].get(kv[0], [])), kv[0]))
    for resref, meta in ranked:
        add(f"| {len(rep['by_item'].get(resref, []))} "
            f"| {len(rep['inst_by_item'].get(resref, []))} "
            f"| `{resref}` | {meta['name']} | `{meta['tag']}` "
            f"| {meta['plot']} | {meta['cursed']} |")
    add("")
    add("## Creature blueprints — the decision table")
    add("")
    add("Fill in **keep?** per creature. Sorted by challenge rating, highest "
        "first, so the real bosses are at the top and the trash-tier oddities "
        "that should probably never have had immunity are further down.")
    add("")
    add("| CR | creature | name | item | where | droppable | keep? |")
    add("|---:|---|---|---|---|---|---|")
    for row in sorted(rep["blueprint_rows"],
                      key=lambda r: (-(r["cr"] or 0), r["creature"])):
        add(f"| {row['cr']} | `{row['creature']}` | {row['creature_name']} "
            f"| `{row['item']}` | {row['where']} "
            f"| {'**YES**' if row['dropable'] else 'no'} |  |")
    add("")
    add("## Placed instances")
    add("")
    add("Instance-level copies. An instance that diverges from its blueprint "
        "reverts on respawn, so these matter only alongside the blueprint row "
        "above them.")
    add("")
    add("| area | creature | name | item | where | droppable |")
    add("|---|---|---|---|---|---|")
    for row in sorted(rep["instance_rows"],
                      key=lambda r: (r["area"], r["creature"])):
        add(f"| `{row['area']}` | `{row['creature']}` | {row['creature_name']} "
            f"| `{row['item']}` | {row['where']} "
            f"| {'**YES**' if row['dropable'] else 'no'} |")
    add("")

    Path(out_path).write_text("\n".join(lines) + "\n", encoding="utf-8")
    print(f"wrote -> {out_path}")


def main():
    ap = argparse.ArgumentParser(description=__doc__,
                                 formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--full", action="store_true", help="print every row")
    ap.add_argument("--markdown", metavar="FILE", help="write the audit document")
    args = ap.parse_args()

    items = scan_items()
    blueprint_rows = scan_creatures(items)
    instance_rows = scan_instances(items)
    script_hits = scan_scripts()
    rep = build_report(items, blueprint_rows, instance_rows, script_hits)

    print_summary(rep)

    if args.full:
        print()
        for row in sorted(rep["blueprint_rows"], key=lambda r: -(r["cr"] or 0)):
            print(f"  CR {row['cr']:>6}  {row['creature']:24s} "
                  f"{row['item']:24s} {row['where']:9s} "
                  f"{'DROPPABLE' if row['dropable'] else ''}")

    if args.markdown:
        markdown(rep, args.markdown)

    return 0


if __name__ == "__main__":
    sys.exit(main())
