#!/usr/bin/env python3
"""Generate unpacked/don_cheat_data.nss - the Donations Chest cheat-stock item table.

The table is the *union*, per equipment slot, of two top-5 lists taken from
module-index/counter_gear.json:

  1. the five most valuable obtainable items in that slot (raw GP value), and
  2. the five items that appear most often in the winning kit ("best_kit") of the
     78 bosses tracked by the Roll of the Fallen board (module-index/bosses.json).

So each slot contributes 5-10 resrefs. Items are dropped from the table when they

  * have no .uti blueprint in unpacked/ (CreateItemOnObject would fail),
  * are not player-obtainable per module-index/item_index.json, or
  * appear in the illicit-donations quarantine list in unpacked/_inc_donations.nss
    (those get confiscated - with a 5x gold refund - the moment the taker walks
    back into the Well of Eru, which would be a gold exploit).

Consumers: don_cheat_inc.nss (restock logic + the DON_CHEAT_ENABLED master switch,
both hand-written) and don_cheat_close.nss (chest OnClosed).

Re-run after a wiki/counter-gear rebuild:  python3 bin/gen-cheat-chest.py
"""
import collections
import json
import os
import re
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
IDX = os.path.join(ROOT, "module-index")
OUT = os.path.join(ROOT, "unpacked", "don_cheat_data.nss")
TOP_N = 5
# base items whose natural stack is a full quiver rather than a single item
AMMO_SLOTS = {"ammo"}

# Hand-curated additions that the top-value / boss-kit ranking can never pick,
# because they are not equipment the counter-gear tables rank at all. Listed
# HERE rather than in the generated table so a regeneration keeps them.
# (resref, display name, stack, why)
EXTRAS = [
    ("mw_mixtape", "Akira's Mixtape", 1,
     "extra: Meaningwave finale reward, so testers can take the permanent +1 "
     "to all six abilities without replaying the 7-guide meta-quest"),
]


def load(name):
    with open(os.path.join(IDX, name), encoding="utf-8") as fh:
        return json.load(fh)


def main():
    EXTRA_STACKS = {}
    cg = load("counter_gear.json")
    bosses = {b["resref"] for b in load("bosses.json")["bosses"]}
    items = {i["resref"]: i for i in load("item_index.json")["items"]}

    with open(os.path.join(ROOT, "unpacked", "_inc_donations.nss"), encoding="utf-8") as fh:
        illicit = set(re.findall(r'sResRef == "([^"]+)"', fh.read()))

    # boss creature records (a boss resref may be a blueprint with several placements)
    by_canon = {c["canonical_resref"]: c for c in cg["creatures"]}
    by_blueprint = collections.defaultdict(list)
    for c in cg["creatures"]:
        by_blueprint[c["blueprint_resref"]].append(c)
    boss_recs = []
    for r in sorted(bosses):
        if r in by_canon:
            boss_recs.append(by_canon[r])
        else:
            boss_recs.extend(by_blueprint.get(r, []))

    used = collections.defaultdict(collections.Counter)
    meta = {}
    for c in boss_recs:
        for it in c.get("best_kit") or []:
            used[it["slot"]][it["resref"]] += 1
            meta[it["resref"]] = it

    rows, skipped = [], []
    for slot in cg["top_value_by_slot"]:
        s = slot["slot"]
        for it in slot["items"]:
            meta.setdefault(it["resref"], it)
        by_value = [i["resref"] for i in slot["items"][:TOP_N]]
        by_use = [r for r, _ in used[s].most_common(TOP_N)]
        picks = []
        for r in list(dict.fromkeys(by_value + by_use)):
            why = ("value" if r in by_value else "") + ("+" if r in by_value and r in by_use else "") \
                  + (f"boss x{used[s][r]}" if r in by_use else "")
            reason = None
            if not os.path.exists(os.path.join(ROOT, "unpacked", f"{r}.uti.json")):
                reason = "no .uti blueprint"
            elif not items.get(r, {}).get("accessible"):
                reason = "not player-obtainable"
            elif r in illicit:
                reason = "illicit-donations quarantine list"
            if reason:
                skipped.append((s, r, meta[r]["name"], reason))
                continue
            picks.append((r, meta[r]["name"], meta[r].get("gp_value") or 0, why))
        rows.append((s, slot["label"], picks))

    # Extras are appended last, as their own section. They skip the
    # player-obtainable test on purpose (a quest-only reward is never
    # "obtainable" by the item index), but still need a real blueprint and
    # must not be on the illicit-donations quarantine list.
    extra_picks = []
    for r, name, stack, why in EXTRAS:
        reason = None
        if not os.path.exists(os.path.join(ROOT, "unpacked", f"{r}.uti.json")):
            reason = "no .uti blueprint"
        elif r in illicit:
            reason = "illicit-donations quarantine list"
        if reason:
            skipped.append(("extra", r, name, reason))
            continue
        extra_picks.append((r, name, 0, why))
        EXTRA_STACKS[r] = stack
    if extra_picks:
        rows.append(("extra", "Extras", extra_picks))

    lines = [
        "// don_cheat_data.nss",
        "// Donations Chest cheat-stock table: per slot, the union of the top-5 items",
        "// by GP value and the top-5 items appearing in the boss-beating kits from",
        "// module-index/counter_gear.json, plus the hand-curated EXTRAS list.",
        "//",
        "// AUTO-GENERATED by bin/gen-cheat-chest.py - do not hand-edit.",
        "// The master on/off switch lives in don_cheat_inc.nss, not here.",
        "",
    ]
    flat = []
    for s, label, picks in rows:
        for r, name, gp, why in picks:
            flat.append((s, label, r, name, gp, why))

    lines.append(f"const int DON_CHEAT_COUNT = {len(flat)};")
    lines.append("")
    lines.append("// Resref of cheat-stock item n (0 .. DON_CHEAT_COUNT-1).")
    lines.append("string DonCheatResRef(int n)")
    lines.append("{")
    lines.append("    switch (n)")
    lines.append("    {")
    last_slot = None
    for i, (s, label, r, name, gp, why) in enumerate(flat):
        if s != last_slot:
            lines.append(f"        // --- {label} ---")
            last_slot = s
        note = why if s == "extra" else f"{gp:,} gp, {why}"
        lines.append(f'        case {i}:'.ljust(20) + f'return "{r}";'.ljust(30)
                     + f"// {name} ({note})")
    lines.append("    }")
    lines.append("    return \"\";")
    lines.append("}")
    lines.append("")
    lines.append("// Stack size for cheat-stock item n - a full quiver for ammunition, else 1.")
    lines.append("int DonCheatStack(int n)")
    lines.append("{")
    lines.append("    switch (n)")
    lines.append("    {")
    for i, (s, label, r, name, gp, why) in enumerate(flat):
        if s in AMMO_SLOTS:
            lines.append(f"        case {i}: // {name}")
    lines.append("            return 99;")
    for i, (s, label, r, name, gp, why) in enumerate(flat):
        n = EXTRA_STACKS.get(r, 1)
        if s == "extra" and n != 1:
            lines.append(f"        case {i}: // {name}")
            lines.append(f"            return {n};")
    lines.append("    }")
    lines.append("    return 1;")
    lines.append("}")
    lines.append("")

    with open(OUT, "w", encoding="utf-8") as fh:
        fh.write("\n".join(lines))

    print(f"wrote {os.path.relpath(OUT, ROOT)}: {len(flat)} items across {len(rows)} slots")
    for s, label, picks in rows:
        print(f"  {label:<12} {len(picks)}")
    if skipped:
        print(f"skipped {len(skipped)}:")
        for s, r, name, reason in skipped:
            print(f"  {s:<8} {r:<18} {name[:34]:<36} {reason}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
