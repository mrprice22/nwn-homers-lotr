#!/usr/bin/env python3
"""Inspect and reset the Crash Party event database (crashpartydb).

The in-game half of the event deliberately tells players nothing about charges
and grants each item once per character, ever. Both of those make the feature
hard to TEST without a tool: you would otherwise need a brand new character for
every dispenser run, and no way at all to see how many charges are left.

This is that tool. It is an admin/UAT utility, not part of the game.

    bin/crash-party-db.py --status              # party state at a glance
    bin/crash-party-db.py --top 10              # drinking leaderboard
    bin/crash-party-db.py --grants              # who has been given what
    bin/crash-party-db.py --reset-grants NAME   # let one character be re-issued
    bin/crash-party-db.py --reset-grants ALL    # ...or everyone (dev realms only)
    bin/crash-party-db.py --set-peak N          # seed/correct the record to beat
    bin/crash-party-db.py --clear-sips          # wipe the drinking contest

Realm selection follows the repo you run it from: it reads NWN_HOME_DIR out of
that repo's server.env, so running it in the dev repo touches the dev realm's
database and nothing else. --realm overrides it.

## What it deliberately cannot do

There is no "take an item back" and no "set charges" here, because charges do
not live in this database -- they are LocalInts on the item object, serialised
into the player's .bic. That is by design: leftover charges are the player's
property and nothing server-side reaches in and removes them. To exercise the
break path in testing, use the DM console's UAT lever instead, which reduces
only the charges on items in the *admin's own* pack.
"""

from __future__ import annotations

import argparse
import os
import re
import sqlite3
import sys
from pathlib import Path

REPO = Path(__file__).resolve().parent.parent
DB_NAME = "crashpartydb.sqlite3"


def read_server_env(repo: Path) -> dict:
    """Pull the handful of vars we need out of server.env without sourcing it."""
    env = {}
    p = repo / "server.env"
    if not p.exists():
        return env
    for line in p.read_text().splitlines():
        m = re.match(r'^\s*([A-Z_][A-Z0-9_]*)=(.*)$', line)
        if not m:
            continue
        k, v = m.group(1), m.group(2).strip()
        v = v.split('#')[0].strip() if not v.startswith(('"', "'")) else v
        v = v.strip().strip('"').strip("'")
        env[k] = os.path.expandvars(v.replace("$HOME", os.path.expanduser("~")))
    return env


def db_path(realm: str | None) -> Path:
    if realm:
        return Path(os.path.expanduser(realm)) / "database" / DB_NAME
    env = read_server_env(REPO)
    home = env.get("NWN_HOME_DIR")
    if not home:
        sys.exit("could not read NWN_HOME_DIR from %s/server.env" % REPO)
    return Path(home) / "database" / DB_NAME


def connect(path: Path, must_exist=True) -> sqlite3.Connection:
    if must_exist and not path.exists():
        sys.exit(
            "no %s\n"
            "The database is created by CP_InitDb() at module load, so this is\n"
            "normal until the module has been rebuilt and the server has started\n"
            "once with the Crash Party code in it." % path)
    return sqlite3.connect(path)


def table_exists(cx, name) -> bool:
    return cx.execute(
        "SELECT 1 FROM sqlite_master WHERE type='table' AND name=?", (name,)
    ).fetchone() is not None


def cmd_status(cx, path):
    print("database: %s" % path)
    for t in ("cp_player", "cp_grant", "cp_state"):
        print("  %-10s %s" % (t, "present" if table_exists(cx, t) else "MISSING"))
    if table_exists(cx, "cp_state"):
        row = cx.execute("SELECT v FROM cp_state WHERE k='peak'").fetchone()
        print("\npeak concurrent recorded in game: %s" % (row[0] if row else "(unset - seeds at 8)"))
    if table_exists(cx, "cp_player"):
        n, sips = cx.execute(
            "SELECT COUNT(*), COALESCE(SUM(sips),0) FROM cp_player").fetchone()
        print("drinkers: %d   total sips: %d" % (n, sips))
    if table_exists(cx, "cp_grant"):
        n, chars = cx.execute(
            "SELECT COUNT(*), COUNT(DISTINCT ident) FROM cp_grant").fetchone()
        print("grants: %d rows across %d character(s)" % (n, chars))


def cmd_top(cx, limit):
    if not table_exists(cx, "cp_player"):
        return print("no cp_player table yet")
    rows = cx.execute(
        "SELECT char_name, sips FROM cp_player WHERE sips>0 "
        "ORDER BY sips DESC, char_name ASC LIMIT ?", (limit,)).fetchall()
    if not rows:
        return print("nobody has taken a drink yet")
    print("Deepest drinkers:")
    for i, (name, sips) in enumerate(rows, 1):
        print("  %2d. %-28s %d" % (i, name or "(unnamed)", sips))


def cmd_grants(cx):
    if not table_exists(cx, "cp_grant"):
        return print("no cp_grant table yet")
    rows = cx.execute(
        "SELECT g.ident, COALESCE(p.char_name,'(unknown)'), GROUP_CONCAT(g.item, ', ') "
        "FROM cp_grant g LEFT JOIN cp_player p ON p.ident=g.ident "
        "GROUP BY g.ident ORDER BY 2").fetchall()
    if not rows:
        return print("nothing has been granted yet")
    for ident, name, items in rows:
        print("  %-28s %s" % (name, items))
        print("  %-28s   [%s]" % ("", ident))


def cmd_reset_grants(cx, who):
    if not table_exists(cx, "cp_grant"):
        return print("no cp_grant table yet")
    if who.upper() == "ALL":
        env = read_server_env(REPO)
        if env.get("SEASON_ROLE") == "live":
            sys.exit("refusing --reset-grants ALL on a LIVE realm; name a character instead")
        n = cx.execute("DELETE FROM cp_grant").rowcount
        cx.commit()
        return print("cleared %d grant row(s) for every character" % n)
    idents = [r[0] for r in cx.execute(
        "SELECT ident FROM cp_player WHERE char_name = ? COLLATE NOCASE", (who,)).fetchall()]
    if not idents:
        return print("no character named %r in cp_player "
                     "(they have to have taken a sip to be listed; "
                     "use --grants to see idents)" % who)
    total = 0
    for ident in idents:
        total += cx.execute("DELETE FROM cp_grant WHERE ident=?", (ident,)).rowcount
    cx.commit()
    print("cleared %d grant row(s) for %s -- the dispenser will re-issue on next entry"
          % (total, who))


def main():
    ap = argparse.ArgumentParser(description=__doc__,
                                 formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--realm", help="override NWN home dir (default: this repo's server.env)")
    ap.add_argument("--status", action="store_true")
    ap.add_argument("--top", type=int, metavar="N")
    ap.add_argument("--grants", action="store_true")
    ap.add_argument("--reset-grants", metavar="NAME_OR_ALL")
    ap.add_argument("--set-peak", type=int, metavar="N")
    ap.add_argument("--clear-sips", action="store_true")
    a = ap.parse_args()

    path = db_path(a.realm)
    if not any([a.status, a.top, a.grants, a.reset_grants, a.set_peak is not None,
                a.clear_sips]):
        a.status = True

    cx = connect(path)
    try:
        if a.status:
            cmd_status(cx, path)
        if a.top:
            cmd_top(cx, a.top)
        if a.grants:
            cmd_grants(cx)
        if a.reset_grants:
            cmd_reset_grants(cx, a.reset_grants)
        if a.set_peak is not None:
            cx.execute("INSERT INTO cp_state (k,v) VALUES ('peak',?) "
                       "ON CONFLICT(k) DO UPDATE SET v=?", (a.set_peak, a.set_peak))
            cx.commit()
            print("peak set to %d" % a.set_peak)
        if a.clear_sips:
            n = cx.execute("UPDATE cp_player SET sips=0").rowcount
            cx.commit()
            print("cleared sip counts for %d character(s)" % n)
    finally:
        cx.close()


if __name__ == "__main__":
    main()
