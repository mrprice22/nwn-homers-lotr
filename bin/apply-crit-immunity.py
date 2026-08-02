#!/usr/bin/env python3
"""Apply the reviewed crit-immunity decisions (roadmap: remove-crit-immunity).

Immunity to critical hits stops being the default. It survives ONLY on creatures
the admin marked to keep it, under one rule, stated 2026-08-02:

    keep crit immunity if and only if it makes thematic sense for the creature
    to be undead -- and Nazgul count as undead.

Everything else loses it. Devastating Critical no longer instant-kills (roadmap
devcrit-roll shipped 2026-08-02), which is what made this safe to do.

HOW THE THREE CASES ARE HANDLED
    Crit immunity is item property 37 / subtype 8, and it lives in TWO places
    that have to move together:
      * the item BLUEPRINT (unpacked/<item>.uti.json), which is what a respawn
        rebuilds from, and
      * an inlined copy inside each placed instance (unpacked/<area>.git.json),
        which is what the creature standing there right now actually has.
    236 instance copies carry the property independently of their blueprint, so
    editing only the blueprint would leave every already-placed creature immune
    until its first death.

    For each crit-immunity item:
      STRIP    no keeper carries it            -> remove the property outright
      LEAVE    every carrier is a keeper       -> untouched
      VARIANT  both                            -> strip the shared blueprint and
               mint <base>_ci carrying the property, then repoint the keepers
               (blueprint AND their placed instances) at the variant

    A variant is needed because the shared blueprints are shared hard --
    npcbuffgear alone is worn by 49 creatures, 8 of them keepers. There is no
    per-creature override that survives respawn: se_respawn_inc.nss rebuilds
    from the blueprint, so a keeper's immunity has to be in a blueprint of its
    own.

    python3 bin/apply-crit-immunity.py           # dry run (default)
    python3 bin/apply-crit-immunity.py --apply

AFTERWARDS
    python3 bin/file-palette-orphans.py --apply   # the new variants must be filed
    python3 bin/audit-crit-immunity.py            # should list only keepers
"""

import argparse
import collections
import glob
import json
import os
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
UNPACKED = os.path.join(ROOT, "unpacked")

PROP_IMMUNITY_MISC = 37
SUBTYPE_CRITICAL_HITS = 8

# ---------------------------------------------------------------------------
# The decision list. Provenance for every entry, because "why is this thing
# still immune" is the question someone will ask in six months.
#
#   (a) the 14 rows the admin marked YES in CLAUDE-devcrit-immunity-audit.md
#   (b) creatures whose blueprint Race is 24 (Undead) in racialtypes.2da --
#       found by spot-check, since a blank decision meant "no" and these would
#       otherwise have been stripped against the admin's own rule
#   (c) Nazgul by name, which are not flagged Undead in their blueprints
#   (d) four judgement calls confirmed by the admin 2026-08-02
#
# Struck deliberately, also 2026-08-02:
#   bettie / doomkghtboss001 / sewermaster001 -- flagged Race=Undead but wearing
#     a Cat, Bat and Bladeling model; the race flag reads as a builder slip
#   creature023 (+_2, ds_) -- "The Rancid Skinner, Green MORTAL of Khamul": a
#     mortal servant of a Nazgul, not one. Khamul himself IS kept.
# ---------------------------------------------------------------------------
KEEP_ADMIN_YES = {
    "modreddm", "surgdm", "halfling002",          # DM avatars
    "ds_witchking",                                # Angmar the Evocator
    "mummyboss001", "weathertopkin004", "thecursedone002",
    "creature007", "creature007_2",                # Khamul The Ringwraith
    "weathertopque003", "mummyreaper", "dracolichii",
    "adunaphelthering", "weathertopfighte",
}
KEEP_RACE_UNDEAD = {
    "weathertopque003", "weathertopque002", "doomkght001", "weathertopkin002",
    "fallenheroofgond", "weathertoparc002", "acidicarcher002",
    "weathertoparcher", "thecursedone", "wonderingsoul", "spectre002",
    "forgottenwarrior", "aforgottensol001", "aforgottensoldio", "gwathspirit",
    "gwathspirit002", "aforgottensol004", "aforgottensol003", "aforgottensol002",
    "thingofthedark", "q_maz_wraith", "guardianoflig002", "guardianofdar002",
}
KEEP_NAZGUL = {
    "witchking", "creature020", "ds_hoarmouth", "hoarmouththering",
    "adunaphelther001", "ds_adunaphel",
}
KEEP_JUDGEMENT = {
    "theexecutionorof", "akhorahil006", "akhorahil006_2", "unnamedhorror",
    "doombeetle",
}
KEEP = KEEP_ADMIN_YES | KEEP_RACE_UNDEAD | KEEP_NAZGUL | KEEP_JUDGEMENT

# Variant resrefs. A resref is capped at 16 characters, which is why two of
# these are abbreviated rather than plain <base>_ci.
VARIANT_RESREF = {
    "bossring":         "bossring_ci",
    "dontdropbossring": "dontdropboss_ci",
    "it_creitem009":    "it_creitem009_ci",
    "it_creitem010":    "it_creitem010_ci",
    "item074":          "item074_ci",
    "npcbuffgear":      "npcbuffgear_ci",
    "npcbuffgear006":   "npcbuffgr006_ci",
}


def gv(node, key, default=None):
    v = node.get(key) if isinstance(node, dict) else None
    return v.get("value") if isinstance(v, dict) else default


def list_of(node, key):
    v = node.get(key)
    if isinstance(v, dict):
        v = v.get("value")
    return v if isinstance(v, list) else []


def has_crit_immunity(node):
    for prop in list_of(node, "PropertiesList"):
        if gv(prop, "PropertyName") == PROP_IMMUNITY_MISC and \
           gv(prop, "Subtype") == SUBTYPE_CRITICAL_HITS:
            return True
    return False


def strip_crit_immunity(node):
    """Remove the property in place. Returns how many were removed."""
    props = node.get("PropertiesList")
    if not isinstance(props, dict) or not isinstance(props.get("value"), list):
        return 0
    before = len(props["value"])
    props["value"] = [
        p for p in props["value"]
        if not (gv(p, "PropertyName") == PROP_IMMUNITY_MISC and
                gv(p, "Subtype") == SUBTYPE_CRITICAL_HITS)
    ]
    return before - len(props["value"])


def item_resref(entry):
    return (gv(entry, "EquippedRes") or gv(entry, "InventoryRes")
            or gv(entry, "TemplateResRef") or "")


def set_item_resref(entry, new):
    for key in ("EquippedRes", "InventoryRes", "TemplateResRef"):
        if isinstance(entry.get(key), dict):
            entry[key]["value"] = new


class Json:
    def __init__(self, path):
        self.path = path
        self.raw = open(path, encoding="utf-8").read()
        self.data = json.loads(self.raw, object_pairs_hook=collections.OrderedDict)
        self.dirty = 0

    def round_trips(self):
        return json.dumps(json.loads(self.raw,
                                     object_pairs_hook=collections.OrderedDict),
                          indent=2, ensure_ascii=False) + "\n" == self.raw

    def write(self):
        open(self.path, "w", encoding="utf-8").write(
            json.dumps(self.data, indent=2, ensure_ascii=False) + "\n")


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
            files[path] = Json(path)
        return files[path]

    # --- which item blueprints grant it, and who carries them ---------------
    crit_items = set()
    for path in sorted(glob.glob(os.path.join(UNPACKED, "*.uti.json"))):
        if has_crit_immunity(json.load(open(path, encoding="utf-8"))):
            crit_items.add(os.path.basename(path)[: -len(".uti.json")])

    carriers = collections.defaultdict(set)
    for path in sorted(glob.glob(os.path.join(UNPACKED, "*.utc.json"))):
        creature = os.path.basename(path)[: -len(".utc.json")]
        data = json.load(open(path, encoding="utf-8"))
        for key in ("Equip_ItemList", "ItemList"):
            for entry in list_of(data, key):
                res = item_resref(entry)
                if res in crit_items:
                    carriers[res].add(creature)

    plan = {}
    for item in sorted(crit_items):
        keepers = carriers[item] & KEEP
        others = carriers[item] - KEEP
        plan[item] = ("variant" if keepers and others
                      else "leave" if keepers else "strip")

    missing = [i for i, k in plan.items() if k == "variant" and i not in VARIANT_RESREF]
    if missing:
        print(f"error: no variant resref defined for {missing}", file=sys.stderr)
        return 1

    log = collections.Counter()

    # --- 1. variants: mint <base>_ci before the base is stripped ------------
    created = []
    for item, kind in sorted(plan.items()):
        if kind != "variant":
            continue
        new = VARIANT_RESREF[item]
        src = os.path.join(UNPACKED, f"{item}.uti.json")
        dst = os.path.join(UNPACKED, f"{new}.uti.json")
        data = json.loads(open(src, encoding="utf-8").read(),
                          object_pairs_hook=collections.OrderedDict)
        if isinstance(data.get("TemplateResRef"), dict):
            data["TemplateResRef"]["value"] = new
        # Its own tag: a duplicate tag makes GetItemPossessedBy return whichever
        # copy the engine finds first, which is exactly the bug class
        # module-index/item_tag_conflicts.json exists to catch.
        if isinstance(data.get("Tag"), dict):
            data["Tag"]["value"] = (gv(data, "Tag") or item)[:11] + "_CI"
        created.append((dst, data, item, new))

    # --- 2. strip the base blueprints ---------------------------------------
    for item, kind in sorted(plan.items()):
        if kind == "leave":
            log["item kept whole"] += 1
            continue
        f = load(os.path.join(UNPACKED, f"{item}.uti.json"))
        n = strip_crit_immunity(f.data)
        if n:
            f.dirty += n
            log["item blueprints stripped"] += 1

    # --- 3. repoint keepers' blueprints at the variant -----------------------
    for path in sorted(glob.glob(os.path.join(UNPACKED, "*.utc.json"))):
        creature = os.path.basename(path)[: -len(".utc.json")]
        if creature not in KEEP:
            continue
        f = load(path)
        for key in ("Equip_ItemList", "ItemList"):
            for entry in list_of(f.data, key):
                res = item_resref(entry)
                if plan.get(res) == "variant":
                    set_item_resref(entry, VARIANT_RESREF[res])
                    f.dirty += 1
                    log["keeper blueprint slots repointed"] += 1

    # --- 4. placed instances -------------------------------------------------
    # The rule here is by CREATURE, not by item: a keeper keeps the inlined
    # property (repointed to the variant where one exists), everything else
    # loses it. That covers instances whose blueprint never listed the item.
    for path in sorted(glob.glob(os.path.join(UNPACKED, "*.git.json"))):
        f = None
        data = json.loads(open(path, encoding="utf-8").read())
        touched = False
        for creature in list_of(data, "Creature List"):
            for key in ("Equip_ItemList", "ItemList"):
                for entry in list_of(creature, key):
                    if has_crit_immunity(entry):
                        touched = True
        if not touched:
            continue
        f = load(path)
        for creature in list_of(f.data, "Creature List"):
            base = gv(creature, "TemplateResRef") or ""
            keeper = base in KEEP
            for key in ("Equip_ItemList", "ItemList"):
                for entry in list_of(creature, key):
                    if not has_crit_immunity(entry):
                        continue
                    if keeper:
                        res = item_resref(entry)
                        if plan.get(res) == "variant":
                            set_item_resref(entry, VARIANT_RESREF[res])
                            f.dirty += 1
                            log["keeper instance slots repointed"] += 1
                    else:
                        f.dirty += strip_crit_immunity(entry)
                        log["instance copies stripped"] += 1

    # --- report / write ------------------------------------------------------
    print("plan by item blueprint:")
    for kind in ("strip", "leave", "variant"):
        names = sorted(i for i, k in plan.items() if k == kind)
        print(f"  {kind:8s} {len(names):3d}"
              + (f"  {', '.join(names)}" if kind != "strip" else ""))
    print()
    for k, v in sorted(log.items()):
        print(f"  {v:5d}  {k}")
    print(f"\n  {len(created):5d}  variant item blueprints to create")

    refused = [p for p, f in files.items() if f.dirty and not f.round_trips()]
    if refused:
        print("\nREFUSED — writing these would reformat them, so nothing was "
              "written:", file=sys.stderr)
        for p in refused:
            print(f"  - {p}", file=sys.stderr)
        return 1

    dirty = {p: f for p, f in files.items() if f.dirty}
    print(f"  {len(dirty):5d}  existing files to change")

    if not args.apply:
        print("\nDry run. Nothing written. Re-run with --apply.")
        return 0

    for dst, data, item, new in created:
        open(dst, "w", encoding="utf-8").write(
            json.dumps(data, indent=2, ensure_ascii=False) + "\n")
        print(f"created {os.path.basename(dst)}  (crit-immune variant of {item})")
    for path, f in sorted(dirty.items()):
        f.write()
    print(f"wrote {len(dirty)} file(s)")
    print("\nNext: python3 bin/file-palette-orphans.py --apply   # file the variants")
    return 0


if __name__ == "__main__":
    sys.exit(main())
