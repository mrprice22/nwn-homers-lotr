#!/usr/bin/env python3
"""Look for Bank of Bree vault-duplication activity in the bankaudit log.

Background
----------
Until the fix for roadmap item `banking-duplicate-exploit`, the vault open
scripts (unpacked/bank_fam_open.nss, unpacked/bank_box_open.nss) retrieved the
stored box from the "bankdb" campaign DB unconditionally.  RetrieveCampaignObject
neither clears nor locks the DB row, so a player who opened the vault, emptied a
box and then broke off the conversation (ESC) could re-open and receive a second
box loaded from the unchanged snapshot -- duplicating its contents.

The only durable trace is the `bankaudit` table (unpacked/bank_box_inc.nss),
which records one row per *commit*:

    id, ts, cdkey, char_name, box_type, box_num, item_count, source

`source` is one of "dialog", "area_exit", "client_leave" (and, post-fix,
"open_family"/"open_strong" for opens and a "+dupes" suffix when the commit had
to destroy duplicate boxes).

Signatures this script reports, per CD key
------------------------------------------
1. **Rapid repeat commits** -- several commits of the *same* box_num within a
   short window.  The exploit loop ends with repeated "I am done with my family
   vault" selections to shed the leftover boxes, so it shows up as a burst.
2. **Sawtooth item counts** -- a box whose item_count drops (items withdrawn)
   and then climbs back to at or above the previous level.  Re-materialising
   contents is the fingerprint of the dupe -- but it is also exactly what a
   family vault used as an alt-to-alt transfer chest looks like, and the audit
   table records no per-item detail that would separate the two.  Expect many
   false positives.
3. **Explicit "+dupes" commits** -- post-fix rows where the commit helper found
   and destroyed extra same-tagged boxes.  These are direct evidence.

Pick the right realm. The three realms keep separate bankdb files and the
unnumbered NWN home directory is the *season 1 archive*, so `--realm s2` (the
default) is what you want when investigating the live server. Row counts are
*commits*, not items -- one vault session writes one row per box.

Everything here is READ-ONLY: the DB is opened in immutable mode and nothing is
written.  Output is for human review -- no automated action is taken, and a hit
is a lead, not a conviction (a player who legitimately opens and closes the
vault repeatedly while sorting inventory can trip signature 1).
"""

import argparse
import os
import sqlite3
import sys
from collections import defaultdict
from datetime import datetime, timedelta


# Realm -> NWN home directory. There are three on this machine and they do NOT
# share a bankdb, so picking the wrong one silently reports the wrong season.
# The unnumbered home is the SEASON 1 ARCHIVE, not the live realm and not dev --
# it is the obvious-looking default and it is almost never the one you want.
REALMS = {
    "s1":  "Neverwinter Nights",       # season 1 archive (read-only history)
    "s2":  "Neverwinter Nights S2",    # LIVE
    "dev": "Neverwinter Nights Dev",   # dev/test realm
}


def realm_db_path(realm: str) -> str:
    home = os.path.join(os.path.expanduser("~"), ".local", "share", REALMS[realm])
    return os.path.join(home, "database", "bankdb.sqlite3")


def default_db_path() -> str:
    """NWN_HOME_DIR wins if set; otherwise the LIVE realm, not the archive."""
    home = os.environ.get("NWN_HOME_DIR")
    if home:
        return os.path.join(home, "database", "bankdb.sqlite3")
    return realm_db_path("s2")


def parse_ts(value):
    """bankaudit.ts is written by SQLite's datetime('now') -> 'YYYY-MM-DD HH:MM:SS'."""
    if not value:
        return None
    for fmt in ("%Y-%m-%d %H:%M:%S", "%Y-%m-%dT%H:%M:%S", "%Y-%m-%d %H:%M:%S.%f"):
        try:
            return datetime.strptime(str(value), fmt)
        except ValueError:
            continue
    return None


def load_rows(db_path, since=None):
    uri = "file:" + db_path.replace("?", "%3f").replace("#", "%23") + "?immutable=1"
    con = sqlite3.connect(uri, uri=True)
    # NWN writes names in windows-1252, so a character called e.g. "Th\u00e9oden"
    # is not valid UTF-8 and the default text factory raises on the whole query.
    con.text_factory = lambda b: b.decode("windows-1252", "replace")
    con.row_factory = sqlite3.Row
    try:
        cur = con.execute(
            "SELECT id, ts, cdkey, char_name, box_type, box_num, item_count, source"
            "  FROM bankaudit ORDER BY cdkey, box_type, box_num, id"
        )
        rows = [dict(r) for r in cur.fetchall()]
    except sqlite3.OperationalError as exc:
        sys.exit(f"error: cannot read bankaudit in {db_path}: {exc}\n"
                 "       (the table is created on first vault commit -- an empty\n"
                 "        or pre-audit DB simply has nothing to report)")
    finally:
        con.close()

    if since is not None:
        rows = [r for r in rows if (parse_ts(r["ts"]) or datetime.min) >= since]
    return rows


# ---------------------------------------------------------------------------
# signatures

def find_bursts(rows, window_secs, min_commits):
    """Signature 1: >= min_commits commits of the same box within window_secs."""
    by_box = defaultdict(list)
    for r in rows:
        if str(r["source"] or "").startswith("open_"):
            continue
        by_box[(r["cdkey"], r["box_type"], r["box_num"])].append(r)

    hits = []
    for key, group in by_box.items():
        group = [g for g in group if parse_ts(g["ts"])]
        group.sort(key=lambda g: parse_ts(g["ts"]))
        i = 0
        while i < len(group):
            j = i
            while (j + 1 < len(group)
                   and parse_ts(group[j + 1]["ts"]) - parse_ts(group[i]["ts"])
                       <= timedelta(seconds=window_secs)):
                j += 1
            if (j - i + 1) >= min_commits:
                hits.append((key, group[i:j + 1]))
                i = j + 1
            else:
                i += 1
    return hits


def find_sawtooth(rows):
    """Signature 2: item_count drops then returns to >= the pre-drop level."""
    by_box = defaultdict(list)
    for r in rows:
        if str(r["source"] or "").startswith("open_"):
            continue
        by_box[(r["cdkey"], r["box_type"], r["box_num"])].append(r)

    hits = []
    for key, group in by_box.items():
        group.sort(key=lambda g: g["id"])
        for a, b, c in zip(group, group[1:], group[2:]):
            qa, qb, qc = a["item_count"], b["item_count"], c["item_count"]
            if qa is None or qb is None or qc is None:
                continue
            if qb < qa and qc >= qa:
                hits.append((key, [a, b, c]))
    return hits


def find_dupe_commits(rows):
    """Signature 3: post-fix commits that destroyed duplicate boxes."""
    return [r for r in rows if "+dupes" in str(r["source"] or "")]


# ---------------------------------------------------------------------------

def fmt(r):
    return (f"    #{r['id']:<7} {r['ts']:<19} {r['box_type']:<6} box {r['box_num']} "
            f"{r['item_count']:>3} items  [{r['source']}]  {r['char_name']}")


def main():
    ap = argparse.ArgumentParser(description=__doc__,
                                 formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--realm", choices=sorted(REALMS),
                    help="which realm's bankdb to read: s2 (LIVE, the default), "
                         "dev, or s1 (season 1 archive). Overrides --db.")
    ap.add_argument("--db", default=default_db_path(),
                    help="explicit path to bankdb.sqlite3 (default: the live realm)")
    ap.add_argument("--days", type=int, default=0,
                    help="only consider rows from the last N days (0 = all)")
    ap.add_argument("--window", type=int, default=300,
                    help="burst window in seconds for signature 1 [default: 300]")
    ap.add_argument("--min-commits", type=int, default=4,
                    help="commits of one box inside the window to flag [default: 4]")
    ap.add_argument("--cdkey", help="restrict the report to one CD key")
    args = ap.parse_args()
    if args.realm:
        args.db = realm_db_path(args.realm)

    if not os.path.exists(args.db):
        sys.exit(f"error: no such file: {args.db}\n"
                 "       set NWN_HOME_DIR or pass --db")

    since = datetime.now() - timedelta(days=args.days) if args.days else None
    rows = load_rows(args.db, since)
    if args.cdkey:
        rows = [r for r in rows if r["cdkey"] == args.cdkey]

    realm = next((r for r, home in REALMS.items()
                  if os.sep + home + os.sep in args.db), "?")
    label = {"s1": "SEASON 1 ARCHIVE", "s2": "SEASON 2 (LIVE)",
             "dev": "DEV/TEST"}.get(realm, "UNKNOWN REALM")
    print(f"bankaudit: {len(rows)} commit rows  --  {label}")
    print(f"           {args.db}")
    if not rows:
        return
    stamps = [parse_ts(r["ts"]) for r in rows if parse_ts(r["ts"])]
    if stamps:
        print(f"           {min(stamps)} .. {max(stamps)}")
    print()

    dupes = find_dupe_commits(rows)
    print(f"== Signature 3: commits that destroyed duplicate boxes ({len(dupes)}) ==")
    print("   Direct evidence. Only produced by the post-fix build.")
    for r in dupes:
        print(fmt(r))
    if not dupes:
        print("    (none)")
    print()

    bursts = find_bursts(rows, args.window, args.min_commits)
    print(f"== Signature 1: >={args.min_commits} commits of one box within "
          f"{args.window}s ({len(bursts)}) ==")
    print("   Suggestive, not conclusive -- a player sorting gear across several alts")
    print("   in one bank visit produces the same burst.")
    for (cdkey, btype, bnum), group in sorted(bursts, key=lambda h: h[0]):
        print(f"  {cdkey}  {btype} box {bnum}  x{len(group)}")
        for r in group:
            print(fmt(r))
    if not bursts:
        print("    (none)")
    print()

    saw = find_sawtooth(rows)
    print(f"== Signature 2: item count drops then fully recovers ({len(saw)}) ==")
    print("   Contents re-materialising is the duplication fingerprint -- but a family")
    print("   vault used to shuttle gear between alts looks identical. Weak lead only.")
    for (cdkey, btype, bnum), group in sorted(saw, key=lambda h: h[0]):
        print(f"  {cdkey}  {btype} box {bnum}")
        for r in group:
            print(fmt(r))
    if not saw:
        print("    (none)")
    print()

    flagged = defaultdict(int)
    for r in dupes:
        flagged[r["cdkey"]] += 1
    for key, _ in bursts:
        flagged[key[0]] += 1
    for key, _ in saw:
        flagged[key[0]] += 1
    print("== Per-CD-key totals (signature hits, all three combined) ==")
    if flagged:
        for cdkey, n in sorted(flagged.items(), key=lambda kv: -kv[1]):
            names = sorted({r["char_name"] for r in rows
                            if r["cdkey"] == cdkey and r["char_name"]})
            print(f"  {cdkey:<12} {n:>4} hits   characters: {', '.join(names) or '-'}")
    else:
        print("  (none)")


if __name__ == "__main__":
    main()
