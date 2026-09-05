#!/usr/bin/env python3
"""Authentication, roles and audit for the roadmap editor.

The editor (bin/roadmap-editor.py) used to bind 0.0.0.0 with no authentication
at all, on the theory that the LAN was the trust boundary. It is now reachable
from the public internet through a Cloudflare Tunnel, and more than one person
uses it, so both halves of that theory are gone.

This module owns the whole story: password hashing, sessions, the role ->
capability table, and an append-only audit log. It is stdlib-only (bcrypt is
not installed on this box and layering packages onto an immutable OS for one
KDF is not worth it -- hashlib.scrypt is in the standard library and is the
right primitive).

SECURITY: the database this writes lives OUTSIDE the repo on purpose. It holds
password hashes and live session tokens, so it falls under the same rule as
bin/seed-admindb.sh -- never commit it, never let nasher pack it, and never
send it to the LAN Gemma box. See the "Admin authorization & secrets" section
of CLAUDE.md.
"""
from __future__ import annotations

import base64
import contextlib
import hashlib
import hmac
import os
import re
import secrets
import sqlite3
import time
from dataclasses import dataclass
from datetime import datetime, timezone
from pathlib import Path

# --------------------------------------------------------------------------
# Capabilities and roles
# --------------------------------------------------------------------------
# A capability is a thing you can DO, named after the action rather than after
# the person -- which is what lets a new role be a one-line addition instead of
# a sweep through the request handlers looking for `role == "admin"`.
CAPS: tuple[str, ...] = (
    "view",             # read the board, the roadmap data, merit balances
    "edit",             # save ideas, tick manual_steps
    "promote_shipped",  # move an item INTO a shipped status (manual/implemented/awarded)
    "merit",            # award/revoke merit and UAT credits (touches the live meritdb)
    "publish",          # regenerate + publish to the wiki, the sign DB and git
    "llm_review",       # accept/revert/reroll the LLM changes ledger
    "palette",          # Palette Finder, including the refresh subprocess
    "serverlog",        # the Monitor page and the realm log tail
    "audit_view",       # read the audit log (Recent changes panel)
    "submit",           # create new ideas (reserved for a future `player` role)
    "uat",              # claim a UAT step, record its result, comment on an idea
    "merit_view",       # look at merit balances and pending redemptions
    "release_notes",       # read the tester/player release notes for the open diff
    "release_notes_admin", # read the ADMIN audience of those notes
)

# Role -> capability set. Deliberately a data table.
#
# `dm` is "everything except the two irreversible-in-public things": promoting
# an item into a shipped status (which publishes it to the roadmap page and the
# in-game Recent Updates sign) and paying merit (which writes the shared,
# cross-season meritdb). A DM CAN publish -- that only republishes what the
# roadmap already says.
#
# Note what `dm` deliberately does NOT restrict: manual_steps, design_questions
# and the uat_credits list itself are fully editable on ANY item, including one
# already implemented or awarded. Adding a UAT check to a shipped item is the
# DM's core job; the ceiling gates an item's own status, never its subtasks.
#
# `tester` is a trusted player who helps validate fixes. It is deliberately NOT
# a weaker `dm`: it has no `edit` at all, which is what makes the "UAT fields
# only" ceiling trustworthy. /api/save posts the WHOLE ideas array and writes
# what it is given, so any role holding `edit` can rewrite any field of any
# item; a per-field filter on that route would be a large thing to get right and
# to keep right as the form grows. Instead a tester's only write paths are the
# three narrow endpoints gated on `uat` (claim a step, record its result,
# comment on an idea), each of which patches exactly one step or appends one
# comment and stamps the player-identifying fields itself.
#
# It also lacks `merit_view`: seeing the whole backlog is the point, but every
# player's merit balance and pending redemptions is not a tester's business.
ROLES: dict[str, set[str]] = {
    "admin": set(CAPS),
    "dm": set(CAPS) - {"promote_shipped", "merit"},
    "tester": {"view", "uat", "serverlog", "release_notes"},
    # nwnbot, the Discord forum <-> roadmap sync. It mirrors forum threads into
    # ideas (`edit`, what /api/save gates on) and appends to an idea's internal
    # `comments` list (`uat`, what /api/idea-comment gates on). Deliberately NOT
    # `promote_shipped` or `merit`: shipping an item and paying merit are the
    # admin's, and enforce_idea_permissions() refuses both for this role
    # independently of anything the bot believes about itself -- which is the
    # point of running it as its own role rather than as a `dm`. Also no
    # `publish`, `audit_view` or `merit_view`: an unattended process has no
    # business republishing the wiki, or reading who changed what and what every
    # player is owed. No `serverlog` either; it never looks at the realm.
    "bot": {"view", "edit", "uat"},
    # Sketch for later; not offered by the CLI until it is wanted. Note it has
    # no `audit_view`: who changed what is staff information, not a player's.
    # "player": {"view", "submit"},
}

ROLE_LABELS = {
    "admin": "Administrator",
    "dm": "Dungeon Master",
    "tester": "Tester",
    "bot": "Sync Bot",
}

# Capabilities a `tester` must never acquire. Asserted by
# bin/roadmap-auth-selftest.py so a later reshuffle of CAPS/ROLES cannot widen
# the role by accident -- this is the whole security story of the tier.
TESTER_FORBIDDEN: frozenset[str] = frozenset((
    "edit", "submit", "promote_shipped", "merit", "publish",
    "llm_review", "palette", "audit_view", "merit_view",
    # A tester reads the `testers` and `players` release notes -- that is the
    # point of the tier. The `admin` audience is a different document: it also
    # carries `hidden` items and the commits no roadmap item claimed, which is
    # staff information for the same reason `audit_view` is.
    "release_notes_admin",
))

# Capabilities the `bot` role must never acquire, asserted the same way. The
# bot is an unattended process holding a password in a file, so the blast
# radius of widening it by accident is larger than for a human tier: it would
# be a robot that can ship items, pay merit and republish the wiki.
BOT_FORBIDDEN: frozenset[str] = frozenset((
    "promote_shipped", "merit", "publish", "llm_review", "palette",
    "serverlog", "audit_view", "merit_view",
    # `submit` is reserved for a future `player` role. The bot creates ideas
    # through /api/save, which gates on `edit`, so it has no need of it.
    "submit",
    # Release notes are written for an audience of people, and the admin
    # audience carries `hidden` items and unclaimed commits besides.
    "release_notes", "release_notes_admin",
))

# Statuses a role without `promote_shipped` may not move an item into. This is
# roadmap_publish.SHIPPED_STATUSES -- the set that reaches the public roadmap
# page and the in-game sign. Kept as a literal here so this module stays
# importable standalone (the CLI and the self-test have no reason to load
# gen-roadmap.py); roadmap-editor.py asserts the two agree at import time.
SHIPPED_STATUSES: frozenset[str] = frozenset(("implemented", "awarded", "manual"))

SESSION_COOKIE = "roadmap_session"
SESSION_DAYS = 30
# Re-stamp a session's expiry at most once a day. Sliding expiry without this
# would write to the DB on literally every request.
SESSION_REFRESH_SECONDS = 24 * 3600

USERNAME_RE = re.compile(r"^[a-z0-9][a-z0-9._-]{1,31}$")

# scrypt parameters. n=2**15 costs ~32 MiB and ~50-100ms per hash on this box:
# slow enough to make an offline guess expensive, fast enough that a login does
# not feel broken. Stored per-hash so these can be raised later without
# invalidating existing passwords.
SCRYPT_N = 2 ** 15
SCRYPT_R = 8
SCRYPT_P = 1
SCRYPT_MAXMEM = 128 * SCRYPT_R * SCRYPT_N * 2   # scrypt() refuses without headroom


def db_path() -> Path:
    """Where the auth DB lives. Outside the repo -- see the module docstring."""
    override = os.environ.get("ROADMAP_AUTH_DB")
    if override:
        return Path(override).expanduser()
    base = os.environ.get("XDG_DATA_HOME") or (Path.home() / ".local" / "share")
    return Path(base).expanduser() / "roadmap-editor" / "auth.sqlite3"


def _now() -> int:
    return int(time.time())


def _iso(ts: int) -> str:
    return datetime.fromtimestamp(ts, timezone.utc).astimezone().isoformat(timespec="seconds")


# --------------------------------------------------------------------------
# Database
# --------------------------------------------------------------------------
# One table per concern. `users` and `sessions` are the live state; `audit` is
# append-only -- read by the CLI and, since the Recent changes panel, by the
# server too, but never updated or deleted by either.
#
# `audit_diff` hangs the per-field before/after of a document write off the
# audit row that recorded it. It is a separate table rather than more text in
# `audit.detail` because detail is capped at 2000 chars below and a single
# impl_notes edit can exceed that on its own.
_SCHEMA = (
    """CREATE TABLE IF NOT EXISTS users (
           username     TEXT PRIMARY KEY,
           pwhash       TEXT NOT NULL,
           role         TEXT NOT NULL,
           display_name TEXT NOT NULL DEFAULT '',
           disabled     INTEGER NOT NULL DEFAULT 0,
           created_at   INTEGER NOT NULL,
           last_login   INTEGER
       )""",
    """CREATE TABLE IF NOT EXISTS sessions (
           token      TEXT PRIMARY KEY,
           username   TEXT NOT NULL,
           created_at INTEGER NOT NULL,
           expires_at INTEGER NOT NULL,
           ip         TEXT NOT NULL DEFAULT '',
           user_agent TEXT NOT NULL DEFAULT ''
       )""",
    """CREATE TABLE IF NOT EXISTS audit (
           id       INTEGER PRIMARY KEY AUTOINCREMENT,
           ts       INTEGER NOT NULL,
           username TEXT NOT NULL DEFAULT '',
           role     TEXT NOT NULL DEFAULT '',
           ip       TEXT NOT NULL DEFAULT '',
           action   TEXT NOT NULL,
           detail   TEXT NOT NULL DEFAULT ''
       )""",
    """CREATE TABLE IF NOT EXISTS audit_diff (
           id       INTEGER PRIMARY KEY AUTOINCREMENT,
           audit_id INTEGER NOT NULL,
           ts       INTEGER NOT NULL,
           idea_id  TEXT NOT NULL DEFAULT '',
           kind     TEXT NOT NULL DEFAULT 'change',
           field    TEXT NOT NULL DEFAULT '',
           before   TEXT,
           after    TEXT
       )""",
    "CREATE INDEX IF NOT EXISTS idx_sessions_user ON sessions(username)",
    "CREATE INDEX IF NOT EXISTS idx_audit_ts ON audit(ts)",
    "CREATE INDEX IF NOT EXISTS idx_audit_user ON audit(username)",
    "CREATE INDEX IF NOT EXISTS idx_audit_diff_audit ON audit_diff(audit_id)",
    "CREATE INDEX IF NOT EXISTS idx_audit_diff_ts ON audit_diff(ts)",
)

# Columns added after the first release. CREATE TABLE IF NOT EXISTS never
# alters an existing table, so a new column needs an explicit guarded ALTER or
# it is simply missing on every DB that already exists -- the same trap
# unpacked/admin_db.nss documents for the in-game admin whitelist.
_MIGRATIONS: tuple[tuple[str, str, str], ...] = (
    # (table, column, DDL fragment)
    # The in-game player name this account speaks for. A login is a username;
    # `uat_credits[].player` has to be a name the meritdb roster (or
    # roadmap-merit-aliases.json) resolves, and the two are not the same string.
    # The server stamps claimed_by / tested_by / uat_credits[].player /
    # comments[].author from this column and NEVER from the request body.
    ("users", "player_name", "player_name TEXT NOT NULL DEFAULT ''"),
)


def connect(path: Path | None = None) -> sqlite3.Connection:
    """Open (creating if needed) the auth DB, with the schema applied."""
    p = path or db_path()
    fresh = not p.exists()
    p.parent.mkdir(parents=True, exist_ok=True)
    conn = sqlite3.connect(str(p), timeout=10.0)
    conn.row_factory = sqlite3.Row
    conn.execute("PRAGMA journal_mode=WAL")
    conn.execute("PRAGMA foreign_keys=ON")
    with conn:
        for stmt in _SCHEMA:
            conn.execute(stmt)
        for table, column, ddl in _MIGRATIONS:
            cols = {r["name"] for r in conn.execute(f"PRAGMA table_info({table})")}
            if column not in cols:
                conn.execute(f"ALTER TABLE {table} ADD COLUMN {ddl}")
    if fresh:
        # Password hashes and live session tokens: nobody else's business, even
        # in a single-user home directory.
        with contextlib.suppress(OSError):
            os.chmod(p, 0o600)
    return conn


# --------------------------------------------------------------------------
# Passwords
# --------------------------------------------------------------------------
def hash_password(password: str, *, n: int = SCRYPT_N, r: int = SCRYPT_R,
                  p: int = SCRYPT_P) -> str:
    """Hash a password into the self-describing `scrypt$n$r$p$salt$hash` form.

    The parameters travel with the hash so they can be raised later without
    stranding existing users.
    """
    if not password:
        raise ValueError("password must not be empty")
    salt = secrets.token_bytes(16)
    dk = hashlib.scrypt(password.encode("utf-8"), salt=salt, n=n, r=r, p=p,
                        dklen=32, maxmem=128 * r * n * 2)
    b64 = lambda b: base64.b64encode(b).decode("ascii")
    return f"scrypt${n}${r}${p}${b64(salt)}${b64(dk)}"


def verify_password(password: str, stored: str) -> bool:
    """Constant-time check of a password against a stored hash.

    Returns False rather than raising on a malformed hash: a corrupted row must
    fail the login, not 500 the server.
    """
    try:
        scheme, n, r, p, salt_b64, hash_b64 = stored.split("$")
        if scheme != "scrypt":
            return False
        n, r, p = int(n), int(r), int(p)
        salt = base64.b64decode(salt_b64)
        expect = base64.b64decode(hash_b64)
        dk = hashlib.scrypt(password.encode("utf-8"), salt=salt, n=n, r=r, p=p,
                            dklen=len(expect), maxmem=128 * r * n * 2)
    except (ValueError, TypeError, MemoryError):
        return False
    return hmac.compare_digest(dk, expect)


# --------------------------------------------------------------------------
# Users
# --------------------------------------------------------------------------
@dataclass(frozen=True)
class User:
    username: str
    role: str
    display_name: str = ""
    disabled: bool = False
    # The in-game player name this account speaks for; "" when unbound. The UAT
    # endpoints refuse rather than guess, because a wrong name here pays merit
    # to the wrong player.
    player_name: str = ""

    @property
    def caps(self) -> set[str]:
        return set(ROLES.get(self.role, ()))

    def can(self, cap: str) -> bool:
        return cap in ROLES.get(self.role, ())

    @property
    def label(self) -> str:
        return self.display_name or self.username

    def public(self) -> dict:
        """The shape handed to the browser (see /api/me)."""
        return {"username": self.username, "role": self.role,
                "role_label": ROLE_LABELS.get(self.role, self.role),
                "display_name": self.label,
                "player_name": self.player_name,
                "caps": sorted(self.caps)}


def _user_from_row(row: sqlite3.Row) -> User:
    keys = row.keys()
    return User(username=row["username"], role=row["role"],
                display_name=row["display_name"] or "",
                disabled=bool(row["disabled"]),
                # Guard the key: a row selected by an older query (or a DB
                # opened before the migration ran) simply has no column.
                player_name=(row["player_name"] or "") if "player_name" in keys else "")


def valid_username(name: str) -> bool:
    return bool(USERNAME_RE.match(name or ""))


def add_user(conn, username: str, password: str, role: str,
             display_name: str = "", player_name: str = "") -> User:
    username = (username or "").strip().lower()
    if not valid_username(username):
        raise ValueError(
            f"invalid username {username!r}: 2-32 chars, lowercase letters, "
            "digits, dot, dash or underscore, starting alphanumeric")
    if role not in ROLES:
        raise ValueError(f"unknown role {role!r}: pick one of {', '.join(sorted(ROLES))}")
    if get_user(conn, username):
        raise ValueError(f"user {username!r} already exists")
    with conn:
        conn.execute(
            "INSERT INTO users (username, pwhash, role, display_name,"
            " player_name, created_at) VALUES (?,?,?,?,?,?)",
            (username, hash_password(password), role, display_name or "",
             player_name or "", _now()))
    return User(username, role, display_name or "", player_name=player_name or "")


def get_user(conn, username: str) -> User | None:
    row = conn.execute("SELECT * FROM users WHERE username=?",
                       ((username or "").strip().lower(),)).fetchone()
    return _user_from_row(row) if row else None


def list_users(conn) -> list[dict]:
    return [dict(r) for r in
            conn.execute("SELECT username, role, display_name, player_name,"
                         " disabled, created_at, last_login FROM users"
                         " ORDER BY username")]


def user_count(conn) -> int:
    return conn.execute("SELECT COUNT(*) FROM users").fetchone()[0]


def set_password(conn, username: str, password: str) -> None:
    _require_user(conn, username)
    with conn:
        conn.execute("UPDATE users SET pwhash=? WHERE username=?",
                     (hash_password(password), username.strip().lower()))
    # A password change is also a "lock everyone else out" gesture. Revoking
    # the sessions is the half people forget, and it is the half that matters
    # if the reason for the change is that the old one leaked.
    revoke_sessions(conn, username)


def set_role(conn, username: str, role: str) -> None:
    _require_user(conn, username)
    if role not in ROLES:
        raise ValueError(f"unknown role {role!r}: pick one of {', '.join(sorted(ROLES))}")
    with conn:
        conn.execute("UPDATE users SET role=? WHERE username=?",
                     (role, username.strip().lower()))
    # Sessions cache nothing, but a demotion should take effect now rather than
    # whenever that browser happens to log in again.
    revoke_sessions(conn, username)


def set_display_name(conn, username: str, name: str) -> None:
    _require_user(conn, username)
    with conn:
        conn.execute("UPDATE users SET display_name=? WHERE username=?",
                     (name or "", username.strip().lower()))


def set_player_name(conn, username: str, name: str) -> None:
    """Bind (or unbind, with "") the in-game player name this account credits.

    No session revoke: unlike a role change this does not remove any power, and
    the endpoints read the column fresh on every request anyway.
    """
    _require_user(conn, username)
    with conn:
        conn.execute("UPDATE users SET player_name=? WHERE username=?",
                     ((name or "").strip(), username.strip().lower()))


def set_disabled(conn, username: str, disabled: bool) -> None:
    _require_user(conn, username)
    with conn:
        conn.execute("UPDATE users SET disabled=? WHERE username=?",
                     (1 if disabled else 0, username.strip().lower()))
    if disabled:
        revoke_sessions(conn, username)


def delete_user(conn, username: str) -> None:
    _require_user(conn, username)
    revoke_sessions(conn, username)
    with conn:
        conn.execute("DELETE FROM users WHERE username=?", (username.strip().lower(),))


def _require_user(conn, username: str) -> User:
    u = get_user(conn, username)
    if not u:
        raise ValueError(f"no such user {username!r}")
    return u


# --------------------------------------------------------------------------
# Sessions
# --------------------------------------------------------------------------
def create_session(conn, username: str, ip: str = "", user_agent: str = "") -> str:
    token = secrets.token_urlsafe(32)
    now = _now()
    with conn:
        conn.execute(
            "INSERT INTO sessions (token, username, created_at, expires_at, ip, user_agent)"
            " VALUES (?,?,?,?,?,?)",
            (token, username, now, now + SESSION_DAYS * 86400,
             ip or "", (user_agent or "")[:200]))
        conn.execute("UPDATE users SET last_login=? WHERE username=?", (now, username))
    return token


def resolve_session(conn, token: str) -> User | None:
    """Token -> User, or None if it is unknown, expired, or the user is gone
    or disabled. Refreshes a sliding expiry at most once a day."""
    if not token:
        return None
    row = conn.execute(
        "SELECT s.token, s.expires_at, u.* FROM sessions s"
        " JOIN users u ON u.username = s.username WHERE s.token=?",
        (token,)).fetchone()
    if row is None:
        return None
    now = _now()
    if row["expires_at"] <= now:
        with conn:
            conn.execute("DELETE FROM sessions WHERE token=?", (token,))
        return None
    if row["disabled"]:
        return None
    if row["expires_at"] - now < (SESSION_DAYS * 86400 - SESSION_REFRESH_SECONDS):
        with conn:
            conn.execute("UPDATE sessions SET expires_at=? WHERE token=?",
                         (now + SESSION_DAYS * 86400, token))
    return _user_from_row(row)


def revoke_session(conn, token: str) -> None:
    with conn:
        conn.execute("DELETE FROM sessions WHERE token=?", (token,))


def revoke_sessions(conn, username: str | None = None) -> int:
    with conn:
        if username:
            cur = conn.execute("DELETE FROM sessions WHERE username=?",
                               (username.strip().lower(),))
        else:
            cur = conn.execute("DELETE FROM sessions")
    return cur.rowcount


def purge_expired_sessions(conn) -> int:
    with conn:
        cur = conn.execute("DELETE FROM sessions WHERE expires_at <= ?", (_now(),))
    return cur.rowcount


def list_sessions(conn, username: str | None = None) -> list[dict]:
    sql = ("SELECT token, username, created_at, expires_at, ip, user_agent"
           " FROM sessions")
    args: tuple = ()
    if username:
        sql += " WHERE username=?"
        args = (username.strip().lower(),)
    sql += " ORDER BY created_at DESC"
    out = []
    for r in conn.execute(sql, args):
        d = dict(r)
        # Never hand a live session token to a listing -- it is a bearer
        # credential, and `roadmap-users.py sessions` is something you might
        # paste into a chat while debugging.
        d["token"] = d["token"][:8] + "..."
        out.append(d)
    return out


# --------------------------------------------------------------------------
# Audit log
# --------------------------------------------------------------------------
# How long the per-field diffs are kept. The audit rows themselves are never
# pruned -- "who changed what, when" is not reconstructible once it is gone --
# but the before/after values attached to them are bulky (both sides of every
# notes edit), so they age out. Losing a six-month-old diff costs nothing that
# the audit line itself does not still record.
DIFF_KEEP_DAYS = 90


def audit(conn, action: str, *, user: User | None = None, ip: str = "",
          detail: str = "", username: str = "") -> int | None:
    """Append one line to the audit log. Never raises.

    Called from request handling, so a failure here must not be able to turn a
    successful save into a 500. A lost audit line is bad; losing the write it
    was describing is worse.

    Returns the new row's id so a caller can hang an `audit_diff` off it, or
    None when the insert was swallowed.
    """
    try:
        with conn:
            cur = conn.execute(
                "INSERT INTO audit (ts, username, role, ip, action, detail)"
                " VALUES (?,?,?,?,?,?)",
                (_now(), (user.username if user else username) or "",
                 user.role if user else "", ip or "", action, (detail or "")[:2000]))
            return cur.lastrowid
    except sqlite3.Error:
        return None


def audit_diff(conn, audit_id: int, ts: int, rows) -> None:
    """Attach per-field before/after rows to one audit entry. Never raises.

    `rows` is an iterable of (idea_id, kind, field, before, after); before/after
    are already JSON-encoded strings, or None for "the field was not there".
    Same contract as audit() above: a failure here must never be able to fail
    the write it was describing.
    """
    rows = list(rows or ())
    if not audit_id or not rows:
        return
    try:
        with conn:
            conn.executemany(
                "INSERT INTO audit_diff"
                " (audit_id, ts, idea_id, kind, field, before, after)"
                " VALUES (?,?,?,?,?,?,?)",
                [(audit_id, ts, r[0], r[1], r[2], r[3], r[4]) for r in rows])
            conn.execute("DELETE FROM audit_diff WHERE ts < ?",
                         (ts - DIFF_KEEP_DAYS * 86400,))
    except sqlite3.Error:
        pass


def read_audit_diff(conn, audit_id: int, idea_id: str = "") -> list[dict]:
    """Every field change recorded against one audit entry, in write order."""
    sql = "SELECT * FROM audit_diff WHERE audit_id=?"
    args: list = [int(audit_id)]
    if idea_id:
        sql += " AND idea_id=?"
        args.append(idea_id)
    sql += " ORDER BY id"
    return [dict(r) for r in conn.execute(sql, args)]


def audit_diff_ids(conn, audit_ids) -> dict[int, dict[str, int]]:
    """{audit_id: {idea_id: fields changed}} for a batch of audit rows.

    One grouped query rather than a lookup per row: the Recent changes panel
    renders up to 500 rows and needs to know which of them have a diff to link.
    """
    ids = [int(i) for i in audit_ids or () if i]
    if not ids:
        return {}
    out: dict[int, dict[str, int]] = {}
    # SQLite's variable limit is 999 by default; chunk rather than risk it.
    for start in range(0, len(ids), 500):
        chunk = ids[start:start + 500]
        marks = ",".join("?" * len(chunk))
        rows = conn.execute(
            f"SELECT audit_id, idea_id, COUNT(*) AS n FROM audit_diff"
            f" WHERE audit_id IN ({marks}) GROUP BY audit_id, idea_id", chunk)
        for r in rows:
            out.setdefault(r["audit_id"], {})[r["idea_id"]] = r["n"]
    return out


def read_audit(conn, *, username: str = "", since: int | None = None,
               limit: int = 100) -> list[dict]:
    sql = "SELECT * FROM audit WHERE 1=1"
    args: list = []
    if username:
        sql += " AND username=?"
        args.append(username.strip().lower())
    if since is not None:
        sql += " AND ts >= ?"
        args.append(since)
    sql += " ORDER BY id DESC LIMIT ?"
    args.append(max(1, int(limit)))
    return [dict(r) for r in conn.execute(sql, args)]


# --------------------------------------------------------------------------
# Login throttling
# --------------------------------------------------------------------------
# In-memory on purpose: it only has to survive as long as the process, a
# restart clearing it is a non-event at this scale, and keeping it out of
# SQLite means a password-guessing flood cannot also become a write flood
# against the DB the sessions live in.
_FAILURES: dict[str, list[float]] = {}
FAIL_WINDOW = 15 * 60
FAIL_LIMIT = 5


def _prune(key: str, now: float) -> list[float]:
    hits = [t for t in _FAILURES.get(key, ()) if now - t < FAIL_WINDOW]
    if hits:
        _FAILURES[key] = hits
    else:
        _FAILURES.pop(key, None)
    return hits


def throttle_check(ip: str, username: str) -> int:
    """Seconds the caller must wait before another attempt (0 = go ahead).

    Both the source address and the account are counted, so one IP cannot spray
    many usernames and one username cannot be sprayed from many IPs.
    """
    now = time.time()
    wait = 0
    for key in (f"ip:{ip}", f"user:{(username or '').lower()}"):
        hits = _prune(key, now)
        if len(hits) >= FAIL_LIMIT:
            wait = max(wait, int(FAIL_WINDOW - (now - hits[0])) + 1)
    return wait


def throttle_fail(ip: str, username: str) -> None:
    now = time.time()
    for key in (f"ip:{ip}", f"user:{(username or '').lower()}"):
        _FAILURES.setdefault(key, []).append(now)


def throttle_clear(ip: str, username: str) -> None:
    _FAILURES.pop(f"ip:{ip}", None)
    _FAILURES.pop(f"user:{(username or '').lower()}", None)


# --------------------------------------------------------------------------
# Login
# --------------------------------------------------------------------------
def authenticate(conn, username: str, password: str) -> User | None:
    """Check a username/password pair. None on any failure.

    Deliberately gives the caller no way to tell "no such user" from "wrong
    password", and burns a comparable amount of time in both cases so the
    difference is not readable off the clock either.
    """
    username = (username or "").strip().lower()
    user = get_user(conn, username)
    row = conn.execute("SELECT pwhash FROM users WHERE username=?",
                       (username,)).fetchone() if user else None
    if row is None:
        # Hash something anyway: an unknown user returning instantly, while a
        # real one takes 80ms, is a username oracle.
        verify_password(password or "x", _DUMMY_HASH)
        return None
    if not verify_password(password or "", row["pwhash"]):
        return None
    if user.disabled:
        return None
    return user


# A well-formed hash of a value nobody can guess, used only to spend time on
# the unknown-user path. Built once at import.
_DUMMY_HASH = hash_password(secrets.token_hex(16))


def bootstrap_hint() -> str:
    """What to tell an operator staring at a login page with no accounts."""
    return ("No roadmap-editor accounts exist yet. Create one on the server with:\n"
            "    python3 bin/roadmap-users.py add <username> --role admin")


# --------------------------------------------------------------------------
# Field-level permissions on a posted roadmap document
# --------------------------------------------------------------------------
# Gating routes is not enough. The editor's browser page posts the ENTIRE
# `ideas` array on every save (see the commit() fetch in roadmap-editor.py), and
# /api/save writes what it is given. So without this check a DM's ordinary save
# could set any item to `implemented`, or flip `merit_awarded`, without ever
# calling a merit endpoint.
#
# The check is deliberately NARROW. It looks at exactly four things:
#   * whether an item is in a shipped status,
#   * whether a shipped item still exists,
#   * the `merit_awarded` flag,
#   * the `awarded` flag inside `uat_credits`.
# Everything else on a shipped item stays fully editable: manual_steps,
# design_questions, the uat_credits list itself, notes, impl_notes, title,
# group. Adding a UAT check to an already-implemented item is exactly what a DM
# is here for -- "the parent is shipped" must never mean "the item is frozen".

def _truthy(v) -> bool:
    return bool(v) and v not in ("", "false", "False", 0)


def _uat_awarded(idea: dict) -> dict[str, bool]:
    """player -> awarded, for the uat_credits on one idea."""
    out: dict[str, bool] = {}
    for entry in idea.get("uat_credits") or []:
        if not isinstance(entry, dict):
            continue
        name = str(entry.get("player") or "").strip()
        if name:
            out[name] = _truthy(entry.get("awarded"))
    return out


def enforce_idea_permissions(caps, posted_ideas, disk_ideas,
                             status_label=None) -> list[str]:
    """Reject document-level changes the caller's capabilities do not allow.

    Returns a list of human-readable errors (empty = allowed). `status_label`
    maps a status id to its display label so the message reads the way the
    board does; it falls back to the raw id.
    """
    caps = set(caps or ())
    errors: list[str] = []
    label = status_label or (lambda s: s)
    disk = {i.get("id"): i for i in (disk_ideas or []) if isinstance(i, dict)}
    posted = {i.get("id"): i for i in (posted_ideas or []) if isinstance(i, dict)}

    if "promote_shipped" not in caps:
        for iid, idea in posted.items():
            new = idea.get("status")
            old = (disk.get(iid) or {}).get("status")
            was, now = old in SHIPPED_STATUSES, new in SHIPPED_STATUSES
            if iid not in disk and now:
                errors.append(
                    f"'{iid}': you cannot create an item directly as "
                    f"“{label(new)}” — that status is administrator-only.")
            elif was != now:
                errors.append(
                    f"'{iid}': only an administrator can move an item "
                    f"{'into' if now else 'out of'} “{label(new if now else old)}”. "
                    f"Everything up to “{label('confirmed')}” is yours to set, "
                    f"and the item's steps and notes stay editable either way.")
        # Deleting a shipped item would erase it from the public roadmap and the
        # in-game sign just as effectively as demoting it.
        for iid, idea in disk.items():
            if iid not in posted and idea.get("status") in SHIPPED_STATUSES:
                errors.append(
                    f"'{iid}': only an administrator can delete a shipped item "
                    f"(“{label(idea.get('status'))}”).")

    if "merit" not in caps:
        for iid, idea in posted.items():
            d = disk.get(iid) or {}
            if _truthy(idea.get("merit_awarded")) != _truthy(d.get("merit_awarded")):
                errors.append(
                    f"'{iid}': the merit-awarded flag records a real payment into "
                    "the shared merit database. Only an administrator can change "
                    "it, and only through the Award / Revoke buttons.")
            new_uat, old_uat = _uat_awarded(idea), _uat_awarded(d)
            for player, awarded in new_uat.items():
                if awarded != old_uat.get(player, False):
                    errors.append(
                        f"'{iid}': only an administrator can change the UAT merit "
                        f"payment for {player}. You can add or remove the credit "
                        "itself; paying it is the Award button.")
            for player, awarded in old_uat.items():
                if awarded and player not in new_uat:
                    errors.append(
                        f"'{iid}': {player}'s UAT credit has already been paid, so "
                        "only an administrator can remove it.")
        for iid, idea in disk.items():
            if iid not in posted and _truthy(idea.get("merit_awarded")):
                errors.append(
                    f"'{iid}': only an administrator can delete an item whose merit "
                    "has already been paid.")

    # Same complaint on many items is noise; keep the message actionable.
    seen, unique = set(), []
    for e in errors:
        if e not in seen:
            seen.add(e)
            unique.append(e)
    return unique[:20]
