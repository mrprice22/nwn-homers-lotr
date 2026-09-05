#!/usr/bin/env python3
"""Publish the placeable-appearance index into the in-game `placeappdb`.

The graffiti easel in the Well of Eru pages through ~9,500 placeable looks. That
table cannot live in a .nss and NWScript cannot read a 2DA, so it goes where the
Recent Updates sign's data goes: a campaign SQLite DB the module reads at
runtime. Same shape as bin/publish-roadmap-db.py.

    python3 bin/gen-placeable-appearances.py    # build module-index/ json
    python3 bin/publish-placeable-db.py --dry-run
    python3 bin/publish-placeable-db.py

placeappdb is a READ-ONLY REFERENCE table -- rebuilt wholesale, never written by
the game -- so re-running it is always safe. No restart needed; the server opens
the campaign DB on each use of the easel.

It is deliberately NOT season-scoped state: it describes the haks, not the
players. It still lands in this repo's own NWN_HOME_DIR/database (via
roadmap_publish.nwn_home_dir), because that is the directory the season this
repo drives actually reads. A new season needs one run of this script, exactly
like it needs one run of bin/season-shared-dbs.sh.
"""
from __future__ import annotations

import argparse
import json
import sqlite3
import sys
from pathlib import Path

REPO = Path(__file__).resolve().parent.parent
sys.path.insert(0, str(REPO / "bin"))

import roadmap_publish as PUB  # noqa: E402

INDEX = REPO / "module-index" / "placeable_appearances.json"

# `meta`, `db` and `migrations` are reserved table names in an NWN:EE campaign
# DB -- using one fails silently, per statement, with SQLITE_AUTH.
SCHEMA = [
    "CREATE TABLE IF NOT EXISTS appearances ("
    " id INTEGER PRIMARY KEY, name TEXT NOT NULL, category TEXT NOT NULL,"
    " model TEXT, sort INTEGER NOT NULL)",
    "CREATE TABLE IF NOT EXISTS categories ("
    " name TEXT PRIMARY KEY, theme TEXT NOT NULL, n INTEGER NOT NULL,"
    " sort INTEGER NOT NULL)",
    "CREATE TABLE IF NOT EXISTS themes ("
    " name TEXT PRIMARY KEY, n INTEGER NOT NULL, sort INTEGER NOT NULL)",
    "CREATE INDEX IF NOT EXISTS idx_app_cat ON appearances(category, sort)",
    "CREATE INDEX IF NOT EXISTS idx_cat_theme ON categories(theme, sort)",
]


def drop_stale(con) -> None:
    """Drop tables whose shape predates this script.

    placeappdb is a pure reference table, rebuilt wholesale, so there is nothing
    to migrate -- and `CREATE TABLE IF NOT EXISTS` would happily leave an older
    `categories` (no `theme` column) in place and then fail every INSERT.
    """
    for t in ("categories", "themes"):
        con.execute(f"DROP TABLE IF EXISTS {t}")


def db_path() -> Path:
    return PUB.nwn_home_dir() / "database" / "placeappdb.sqlite3"


def main() -> int:
    ap = argparse.ArgumentParser(
        description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--dry-run", action="store_true",
                    help="print what would be written, write nothing")
    args = ap.parse_args()

    if not INDEX.exists():
        print(f"missing {INDEX.relative_to(REPO)} -- run "
              "`python3 bin/gen-placeable-appearances.py` first", file=sys.stderr)
        return 1
    data = json.loads(INDEX.read_text(encoding="utf-8"))
    entries = data["entries"]
    cats = data["categories"]
    themes = data["themes"]

    # `sort` is the row's position *within its category*, which is the offset
    # the in-game LIMIT/OFFSET paging counts in. Categories sort by name.
    app_rows, seen = [], {}
    for e in entries:
        n = seen.get(e["category"], 0)
        seen[e["category"]] = n + 1
        app_rows.append((e["id"], e["name"], e["category"], e["model"], n))
    # `sort` on a category is its position *within its theme*, for the same
    # reason: it is the OFFSET the in-game category page counts in.
    cat_rows, seen_t = [], {}
    for c in cats:
        n = seen_t.get(c["theme"], 0)
        seen_t[c["theme"]] = n + 1
        cat_rows.append((c["name"], c["theme"], c["count"], n))
    theme_rows = [(t["name"], t["categories"], i) for i, t in enumerate(themes)]

    db = db_path()
    print(f"{len(app_rows)} appearances / {len(cat_rows)} categories / "
          f"{len(theme_rows)} themes -> {db}")
    if args.dry_run:
        for t in theme_rows:
            print(f"  {t[2]} {t[0]:<28} {t[1]} categories")
        return 0

    db.parent.mkdir(parents=True, exist_ok=True)
    con = sqlite3.connect(str(db))
    try:
        drop_stale(con)
        for stmt in SCHEMA:
            con.execute(stmt)
        con.execute("DELETE FROM appearances")
        con.executemany(
            "INSERT INTO appearances(id,name,category,model,sort)"
            " VALUES(?,?,?,?,?)", app_rows)
        con.executemany(
            "INSERT INTO categories(name,theme,n,sort) VALUES(?,?,?,?)", cat_rows)
        con.executemany(
            "INSERT INTO themes(name,n,sort) VALUES(?,?,?)", theme_rows)
        con.commit()
    finally:
        con.close()
    print(f"wrote {db}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
