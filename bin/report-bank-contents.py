#!/usr/bin/env python3
"""Report Bank of Bree vault activity and current vault contents for one realm.

Two things live in the "bankdb" campaign DB and they answer different questions:

* `bankaudit` -- one row per box per commit (ts, cdkey, char_name, box_type,
  box_num, item_count, source).  This is the only *dated history* there is, but
  it records item COUNTS ONLY.  There is no per-item detail in it at all, so no
  report drawn from it can be broken down by item resref.

* the `db` table -- the boxes themselves, stored by StoreCampaignObject as
  zstd-compressed GFF (a UTI whose ItemList holds a full struct per contained
  item).  This is where resrefs, stack sizes and costs live, but it is a
  CURRENT SNAPSHOT: the campaign DB keeps only the latest object per key, so
  there is no history and nothing to sort by date.

Hence the two sections below.  Joining them per item is not possible with the
data the module records today.

Personal strongboxes are owner-scoped, so their `db.playerid` is the player
account name concatenated with the character name.  Family boxes are keyed by
CD key alone (that is what makes them shared across an account), so player names
for those are resolved from veteran_grant, then from the personal-box playerids,
then from character names seen in bankaudit.

Read-only: the DB is opened immutable and nothing is written.
"""

import argparse
import importlib.util
import json
import os
import sqlite3
import sys
from collections import defaultdict

HERE = os.path.dirname(os.path.abspath(__file__))
REPO = os.path.dirname(HERE)

REALMS = {
    "s1":  "Neverwinter Nights",       # season 1 archive
    "s2":  "Neverwinter Nights S2",    # LIVE
    "dev": "Neverwinter Nights Dev",   # dev/test
}
REALM_LABEL = {"s1": "SEASON 1 ARCHIVE", "s2": "SEASON 2 (LIVE)", "dev": "DEV/TEST"}


def realm_db_path(realm):
    return os.path.join(os.path.expanduser("~"), ".local", "share",
                        REALMS[realm], "database", "bankdb.sqlite3")


def load_gff_reader():
    """Reuse the GFF/campaign-DB decoder already written for the forge quarantine."""
    path = os.path.join(HERE, "list-forge-quarantine.py")
    spec = importlib.util.spec_from_file_location("lfq", path)
    mod = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(mod)
    return mod


def load_item_names():
    """resref -> (name, base_item, cost_gp) from the generated module index."""
    path = os.path.join(REPO, "module-index", "item_index.json")
    if not os.path.exists(path):
        return {}
    with open(path, encoding="utf-8") as fh:
        data = json.load(fh)
    return {it["resref"]: (it.get("name", "").strip(),
                           it.get("base_item", ""),
                           it.get("cost_gp"))
            for it in data.get("items", [])}


def connect(db_path):
    uri = "file:" + db_path.replace("?", "%3f").replace("#", "%23") + "?immutable=1"
    con = sqlite3.connect(uri, uri=True)
    # NWN writes names in windows-1252; the default text factory raises on them.
    con.text_factory = lambda b: b.decode("windows-1252", "replace")
    return con


# ---------------------------------------------------------------------------
# player-name resolution

def build_player_map(con):
    """cdkey -> player account name, best effort, plus charname -> player."""
    by_cdkey, by_char = {}, {}

    try:
        for cdkey, player in con.execute(
                "SELECT cdkey, player FROM veteran_grant WHERE player IS NOT NULL AND player <> ''"):
            by_cdkey[cdkey] = player
    except sqlite3.OperationalError:
        pass

    # Personal boxes: playerid is <account><charname>, truncated to 20 chars by
    # the engine. Recover the account by matching the tail against a known
    # character name from bankaudit.
    charnames = {r[0] for r in con.execute(
        "SELECT DISTINCT char_name FROM bankaudit WHERE char_name IS NOT NULL")}
    playerids = {r[0] for r in con.execute(
        "SELECT DISTINCT playerid FROM db WHERE playerid <> ''")}
    for pid in playerids:
        for cn in charnames:
            if cn and len(cn) > 3 and pid.endswith(cn[:len(pid) - 1]) and pid != cn:
                by_char[cn] = pid[:len(pid) - len(cn[:len(pid) - 1])]
                break

    # Fill any CD key still unknown from the character names it committed under.
    for cdkey, cn in con.execute(
            "SELECT DISTINCT cdkey, char_name FROM bankaudit"):
        if cdkey in by_cdkey:
            continue
        if cn in by_char:
            by_cdkey[cdkey] = by_char[cn]
    return by_cdkey, by_char


def player_of(cdkey, by_cdkey):
    return by_cdkey.get(cdkey) or f"(unknown:{cdkey})"


# ---------------------------------------------------------------------------
# section 1: the dated commit history

def report_history(con, by_cdkey, out):
    rows = [dict(zip(
        ("id", "ts", "cdkey", "char_name", "box_type", "box_num", "item_count", "source"), r))
        for r in con.execute(
            "SELECT id, ts, cdkey, char_name, box_type, box_num, item_count, source"
            "  FROM bankaudit")]

    for r in rows:
        r["player"] = player_of(r["cdkey"], by_cdkey)
    # player -> box -> date. There is no resref to sort by; see the module docstring.
    rows.sort(key=lambda r: (r["player"].lower(), r["box_type"], r["box_num"],
                             r["ts"] or "", r["id"]))

    out(f"## Section 1 -- commit history ({len(rows)} rows)")
    out("")
    out("One row per box per commit. `bankaudit` records item COUNTS only, so this")
    out("section cannot be broken down by item resref -- see Section 2 for resrefs.")
    out("Sorted by player, then box, then date.")
    out("")
    current = None
    for r in rows:
        key = (r["player"], r["box_type"], r["box_num"])
        if key != current:
            current = key
            out("")
            out(f"### {r['player']}  [{r['cdkey']}]  --  {r['box_type']} box {r['box_num']}")
            out(f"    {'date':<20} {'items':>5}  {'source':<14} character")
        out(f"    {str(r['ts']):<20} {r['item_count']:>5}  {str(r['source']):<14} {r['char_name']}")
    out("")


# ---------------------------------------------------------------------------
# section 2: current contents, by resref

def report_contents(con, by_cdkey, lfq, names, out):
    boxes = con.execute(
        "SELECT varname, playerid, payload, compressed FROM db WHERE vartype=79"
        " ORDER BY varname, playerid").fetchall()

    entries = []
    failures = []
    for varname, playerid, payload, compressed in boxes:
        if varname.startswith("fam_box_"):
            cdkey = varname[len("fam_box_"):].rsplit("_", 1)[0]
            box_label = f"family box {varname.rsplit('_', 1)[1]}"
            player = player_of(cdkey, by_cdkey)
            owner = ""
        elif varname.startswith("bank_box_"):
            cdkey = ""
            box_label = f"strong box {varname.rsplit('_', 1)[1]}"
            player = playerid  # <account><charname>, best we have for these
            owner = playerid
        else:
            continue

        try:
            raw = lfq.extract_gff(bytes(payload), compressed)
            g = lfq.Gff(raw)
            f = g.top_fields()
            tag = g.value("Tag", f)
            if cdkey == "" and tag and tag.startswith("az_strongbox_"):
                cdkey = tag[len("az_strongbox_"):].rsplit("_", 1)[0]
                resolved = by_cdkey.get(cdkey)
                if resolved:
                    player = resolved
            for sidx in g.list_struct_indices("ItemList", f):
                sf = g.struct_fields(sidx)
                resref = (g.value("TemplateResRef", sf) or "").lower()
                nm, base, cost = names.get(resref, (None, "", None))
                label = nm or g.value("LocalizedName", sf) or "(unnamed)"
                entries.append({
                    "player": player, "cdkey": cdkey, "box": box_label,
                    "owner": owner, "resref": resref, "name": label,
                    "base": base, "stack": g.value("StackSize", sf) or 1,
                    "cost": cost if cost is not None else g.value("Cost", sf),
                })
        except Exception as exc:                      # noqa: BLE001 - report, don't abort
            failures.append(f"{varname}|{playerid}: {exc}")

    # player -> resref. No per-item date exists; see the module docstring.
    entries.sort(key=lambda e: (e["player"].lower(), e["resref"], e["box"]))

    out(f"## Section 2 -- current vault contents ({len(entries)} items in {len(boxes)} boxes)")
    out("")
    out("Decoded from the stored box objects. This is a SNAPSHOT -- the campaign DB")
    out("keeps only the latest object per key, so there is no date to sort by.")
    out("Sorted by player, then item blueprint resref.")
    out("")
    current = None
    for e in entries:
        if e["player"] != current:
            current = e["player"]
            total = sum(x["cost"] or 0 for x in entries if x["player"] == current)
            out("")
            out(f"### {e['player']}"
                + (f"  [{e['cdkey']}]" if e["cdkey"] else "")
                + f"  --  {sum(1 for x in entries if x['player'] == current)} items,"
                + f" {total:,} gp")
            out(f"    {'resref':<20} {'x':>3}  {'gp':>12}  {'box':<14} name")
        out(f"    {e['resref']:<20} {e['stack']:>3}  "
            f"{(e['cost'] or 0):>12,}  {e['box']:<14} {e['name']}")
    out("")

    if failures:
        out("### boxes that could not be decoded")
        for f in failures:
            out(f"    {f}")
        out("")

    # Duplicate-hunting aid: the same resref held more than once by one account.
    out("### same resref held more than once by the same player")
    out("")
    out("Not proof of anything on its own -- stacks of consumables and matched gear")
    out("sets look identical -- but a repeated unique/epic item is worth a look.")
    out("")
    by_pair = defaultdict(list)
    for e in entries:
        by_pair[(e["player"], e["resref"])].append(e)
    any_dupe = False
    for (player, resref), group in sorted(by_pair.items(),
                                          key=lambda kv: (kv[0][0].lower(), kv[0][1])):
        if len(group) < 2:
            continue
        any_dupe = True
        boxes_txt = ", ".join(sorted(g["box"] for g in group))
        out(f"    {player:<16} {resref:<20} x{len(group)}  ({boxes_txt})  {group[0]['name']}")
    if not any_dupe:
        out("    (none)")
    out("")


def main():
    ap = argparse.ArgumentParser(description=__doc__,
                                 formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--realm", choices=sorted(REALMS), default="s2",
                    help="which realm's bankdb to read [default: s2 (LIVE)]")
    ap.add_argument("--db", help="explicit path to bankdb.sqlite3 (overrides --realm)")
    ap.add_argument("-o", "--out", help="write the report to this file instead of stdout")
    args = ap.parse_args()

    db_path = args.db or realm_db_path(args.realm)
    if not os.path.exists(db_path):
        sys.exit(f"error: no such file: {db_path}")

    lines = []
    out = lines.append

    con = connect(db_path)
    try:
        by_cdkey, _ = build_player_map(con)
        out(f"# Bank of Bree vault report -- {REALM_LABEL.get(args.realm, '?')}")
        out("")
        out(f"    source: {db_path}")
        span = con.execute("SELECT min(ts), max(ts), count(*) FROM bankaudit").fetchone()
        out(f"    bankaudit: {span[2]} commit rows, {span[0]} .. {span[1]}")
        out("")
        report_history(con, by_cdkey, out)
        report_contents(con, by_cdkey, load_gff_reader(), load_item_names(), out)
    finally:
        con.close()

    text = "\n".join(lines) + "\n"
    if args.out:
        with open(args.out, "w", encoding="utf-8") as fh:
            fh.write(text)
        print(f"wrote {args.out} ({len(lines)} lines)")
    else:
        sys.stdout.write(text)


if __name__ == "__main__":
    main()
