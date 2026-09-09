#!/usr/bin/env python3
"""list-mw-legacy-pending - list Meaningwave finale/mixtape_consumed rows
that MW_MigrateLegacy() (unpacked/mw_db.nss) found on a character's first
post-fix login but did not auto-migrate, because doing so on a name match
alone risks either double-granting the permanent +1-all-stats Mixtape
reward or reattaching it to a character that never earned it (see the
comment above MW_MigrateLegacy in mw_db.nss, and roadmap:
mw-mixtape-per-character).

Each row is one character's evidence that the OLD, CD-key+name-scoped
campaign DB thought it already had "finale" or "mixtape_consumed" set. The
admin decides, per row, whether to actually seed the new per-character flag
(the character genuinely already finished the questline) or leave it alone
(the row belongs to a namesake predecessor, or is otherwise not this
character's to inherit).

Usage:
  bin/list-mw-legacy-pending.py                  # every realm found beside this repo
  bin/list-mw-legacy-pending.py --realm dev      # by SEASON_ROLE, repeatable
  bin/list-mw-legacy-pending.py --grant PID FLAG --realm dev
                                                  # seed mw_flag for one reviewed row
                                                  # (and clear it from the pending table)
  bin/list-mw-legacy-pending.py --dismiss PID FLAG --realm dev
                                                  # drop a row with no grant
"""
import argparse
import os
import re
import sqlite3
import sys
from pathlib import Path

REPO = Path(__file__).resolve().parent.parent


def env_get(text, key):
    m = re.search(rf'^{key}=["\']?(.*?)["\']?\s*(?:#.*)?$', text, re.M)
    return m.group(1).strip() if m else ""


def realms(wanted):
    out = []
    for repo in sorted(REPO.parent.glob("nwn_homers_lotr*")):
        env_file = repo / "server.env"
        try:
            text = env_file.read_text(encoding="utf-8")
        except OSError:
            continue
        role = env_get(text, "SEASON_ROLE") or "?"
        home = env_get(text, "NWN_HOME_DIR")
        if not home:
            continue
        home = Path(os.path.expandvars(home.replace("$HOME", str(Path.home()))))
        if wanted and role not in wanted:
            continue
        out.append((role, repo.name, home))
    return out


def main():
    ap = argparse.ArgumentParser(description=__doc__,
                                 formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--realm", action="append", default=[], metavar="ROLE")
    ap.add_argument("--grant", nargs=2, metavar=("PID", "FLAG"))
    ap.add_argument("--dismiss", nargs=2, metavar=("PID", "FLAG"))
    args = ap.parse_args()

    targets = realms(args.realm)
    if not targets:
        sys.exit("error: no realm found beside this repo"
                 + (f" with SEASON_ROLE in {args.realm}" if args.realm else ""))
    if (args.grant or args.dismiss) and len(targets) != 1:
        sys.exit("error: --grant/--dismiss needs exactly one realm; pass --realm")

    for role, name, home in targets:
        db_path = home / "database" / "meaningwavedb.sqlite3"
        if not db_path.exists():
            print(f"{role} ({name}): no meaningwavedb.sqlite3 yet at {db_path}")
            continue

        if args.grant:
            pid, flag = args.grant
            conn = sqlite3.connect(db_path)
            conn.execute(
                "INSERT OR IGNORE INTO mw_flag(pid, flag, cdkey) "
                "SELECT pid, flag, cdkey FROM mw_legacy_pending WHERE pid=? AND flag=?",
                (pid, flag))
            n = conn.execute("SELECT changes()").fetchone()[0]
            conn.execute("DELETE FROM mw_legacy_pending WHERE pid=? AND flag=?", (pid, flag))
            conn.commit()
            conn.close()
            print(f"{role}: granted {flag} to {pid} ({n} row written)" if n
                  else f"{role}: {pid}/{flag} not found in mw_legacy_pending, or already granted")
            continue

        if args.dismiss:
            pid, flag = args.dismiss
            conn = sqlite3.connect(db_path)
            conn.execute("DELETE FROM mw_legacy_pending WHERE pid=? AND flag=?", (pid, flag))
            conn.commit()
            conn.close()
            print(f"{role}: dismissed {pid}/{flag}")
            continue

        conn = sqlite3.connect(f"file:{db_path}?mode=ro", uri=True)
        rows = list(conn.execute(
            "SELECT pid, flag, cdkey, name, found_at FROM mw_legacy_pending "
            "ORDER BY found_at"))
        conn.close()
        print(f"\n=== {role} ({name}) ===")
        if not rows:
            print("  (none pending)")
            continue
        for pid, flag, cdkey, char_name, found_at in rows:
            print(f"  {found_at}  flag={flag:16} cdkey={cdkey:14} "
                  f"name={char_name!r:30} pid={pid}")
        print(f"  {len(rows)} row(s) - resolve with "
              f"--grant/--dismiss PID FLAG --realm {role}")


if __name__ == "__main__":
    sys.exit(main())
