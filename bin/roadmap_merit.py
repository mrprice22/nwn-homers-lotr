#!/usr/bin/env python3
"""Read-only access to the in-game merit database, and the roadmap-name bridge.

Extracted from bin/roadmap-editor.py so the account CLI can use it too. The
editor resolves a roadmap player name to a meritdb row when it PAYS merit;
bin/roadmap-users.py resolves the same name when it BINDS an account to a
player. Those two answers have to agree — a binding the award path can't
resolve is a tester who works for weeks and then cannot be paid — so there is
exactly one implementation of the rule, here.

The editor is a 6k-line HTTP server with a hyphenated filename; it cannot be
imported. This module is deliberately small and import-safe: stdlib plus
roadmap_publish for nwn_home_dir(), no yaml, no server.
"""
from __future__ import annotations

import json
import os
import re
import sqlite3
from pathlib import Path

import roadmap_publish as PUB

REPO = Path(__file__).resolve().parent.parent

SHARED_DB_DIR = Path(
    os.environ.get("NWN_SHARED_DIR", Path.home() / ".local/share/nwn-shared"))

# Roadmap player name -> meritdb cdkey, for names the fuzzy matcher can't reach
# ("Piskan (Alec Cain)" vs the DB's "Alek Cain"). Written when you pick a player
# by hand in the award dialog or in `roadmap-users.py setup`, so the same name
# resolves silently next time.
MERIT_ALIAS_PATH = REPO / "roadmap-merit-aliases.json"


def merit_db_path() -> Path:
    """Filesystem path to the live meritdb campaign database.

    This resolves through THIS repo's NWN_HOME_DIR, which is correct only
    because meritdb is a cross-season shared file: every environment's
    database/meritdb.sqlite3 is an absolute symlink to
    ~/.local/share/nwn-shared/meritdb.sqlite3 (bin/season-shared-dbs.sh). So an
    award written from the dev realm lands in the same ledger production reads,
    which is the whole reason merit survives a cutover.

    It is also exactly the kind of assumption that breaks silently. If the
    symlink is missing -- a new season booted before season-shared-dbs.sh ran,
    so nwserver created a plain file -- then this path still exists, still
    opens, and still accepts writes. Merit would be awarded into a per-season
    file that nothing else reads and the next cutover discards, and the editor
    would report success every time.

    That failure has a precedent in this codebase: the roadmapdb publisher's
    fallback path silently wrote season 1's database dir after the cutover (see
    roadmap_publish.nwn_home_dir). Do not leave the shared case to chance.
    """
    return PUB.nwn_home_dir() / "database" / "meritdb.sqlite3"


def merit_db_problem() -> str:
    """Return '' if meritdb is safe to write, else a human-readable reason.

    Checked before every award/revoke, not at startup: the symlink can be
    replaced under a running editor by a server boot.
    """
    db = merit_db_path()
    if not db.exists():
        return f"meritdb not found at {db}"
    if not db.is_symlink():
        return (f"{db} is a REGULAR FILE, not a symlink into {SHARED_DB_DIR}. "
                "Merit written here is per-season and will be lost at the next "
                "cutover. Fix: stop the server and run bin/season-shared-dbs.sh "
                "--apply, then confirm the balances.")
    target = db.resolve()
    try:
        target.relative_to(SHARED_DB_DIR.resolve())
    except ValueError:
        return (f"{db} resolves to {target}, which is outside the shared DB "
                f"directory {SHARED_DB_DIR}. Refusing to write merit to an "
                "unexpected location.")
    return ""


def merit_text(b):
    """Decode a meritdb text column that may not be valid UTF-8.

    Player names come straight off the NWN client, which is not UTF-8 clean —
    meritdb holds at least one Latin-1/CP1252 name ("\xe8eles66C"). sqlite3's
    default text factory raises OperationalError on such a row, which took the
    WHOLE /api/meritplayers response down (a 500, so the picker rendered "No
    merit database players to choose from"). Decode leniently instead: one bad
    byte must never hide the other 73 players.
    """
    if isinstance(b, str):
        return b
    try:
        return b.decode("utf-8")
    except UnicodeDecodeError:
        return b.decode("cp1252", errors="replace")


def merit_connect():
    """Open meritdb read-only, or return None if it can't be read."""
    db = merit_db_path()
    if not db.exists():
        return None
    con = sqlite3.connect(f"file:{db}?mode=ro", uri=True)
    con.text_factory = merit_text
    con.row_factory = sqlite3.Row
    return con


def has_note_column(con) -> bool:
    """Whether meritdb's redemptions table has the `note` column yet.

    Optional for exactly the same reason as `uat` below: the column is added by
    Merit_InitDb() at module load (unpacked/merit_db.nss), meritdb is shared
    across seasons, and a realm that has not yet loaded a module carrying that
    migration still has the old table.
    """
    try:
        return any(r[1] == "note" for r in
                   con.execute("PRAGMA table_info(redemptions)").fetchall())
    except sqlite3.Error:
        return False


def has_uat_column(con) -> bool:
    """Whether meritdb's players table has the `uat` column yet.

    The column is added by Merit_InitDb() at module load (unpacked/merit_db.nss),
    so between deploying this editor and the server's next reboot — and on the
    live realm, which shares this database but loads its own module — it may not
    exist. Every read must therefore treat it as optional rather than throw.
    """
    try:
        return any(r[1] == "uat" for r in
                   con.execute("PRAGMA table_info(players)").fetchall())
    except sqlite3.Error:
        return False


def row_uat(row) -> int:
    """players.uat for a row that may predate the column."""
    try:
        return row["uat"] or 0
    except (IndexError, KeyError):
        return 0


def read_merit_aliases() -> dict:
    try:
        data = json.loads(MERIT_ALIAS_PATH.read_text(encoding="utf-8"))
    except (OSError, ValueError):
        return {}
    return data if isinstance(data, dict) else {}


def write_merit_alias(roadmap_name: str, cdkey: str) -> None:
    aliases = read_merit_aliases()
    aliases[roadmap_name] = cdkey
    MERIT_ALIAS_PATH.write_text(
        json.dumps(dict(sorted(aliases.items())), indent=2) + "\n",
        encoding="utf-8")


def name_candidates(roadmap_name: str) -> list[str]:
    """Strings to try matching a roadmap player name against players.name.

    Roadmap names are free text and often carry a parenthetical alias, e.g.
    "dc0960 (Dungeon_Crawler)" or "HomelessSon (Server Admin)". We try the full
    string, the part before '(', and the part inside '(...)'.
    """
    out: list[str] = []
    n = (roadmap_name or "").strip()
    if n:
        out.append(n)
    m = re.match(r"^([^(]+?)\s*\(([^)]*)\)\s*$", n)
    if m:
        for part in (m.group(1).strip(), m.group(2).strip()):
            if part and part not in out:
                out.append(part)
    return out


def resolve_player_row(con, roadmap_name: str):
    """Smart-match a roadmap player name to a meritdb players row (or None)."""
    for cand in name_candidates(roadmap_name):
        row = con.execute(
            "SELECT * FROM players WHERE name = ? COLLATE NOCASE LIMIT 1",
            (cand,)).fetchone()
        if row:
            return row
    return None


def resolve_with_alias(con, roadmap_name: str):
    """The full award-time lookup: alias file first, then the fuzzy match.

    This is the order award_merit() uses, so a name that resolves here is a name
    the Award +1 button can pay.
    """
    key = read_merit_aliases().get(roadmap_name)
    if key:
        row = con.execute("SELECT * FROM players WHERE cdkey = ?",
                          (key,)).fetchone()
        if row is not None:
            return row
    return resolve_player_row(con, roadmap_name)
