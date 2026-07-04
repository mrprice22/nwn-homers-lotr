#!/usr/bin/env python3
"""Local web GUI for editing the `ideas` backlog in roadmap.yaml.

roadmap.yaml is the source of truth for the public dev roadmap AND the merit-
tracking backlog (shipped player ideas credit a submitter with Merit). It is
edited constantly and typo-prone in the places that matter most: player names,
group ids, statuses, and dupe_of references. This tool serves a small browser
form whose pickers are sourced from the file's own existing values, so those
fields can't drift on a typo. It validates with gen-roadmap.py's own validate()
before writing, and only rewrites the `ideas:` block (the last top-level key),
preserving the header comments and the meta/groups/redemption/housing blocks
verbatim. Per-item leading comment blocks (the section headers) travel with
their item by id.

Usage:
    python3 bin/roadmap-editor.py            # serve + open a browser
    python3 bin/roadmap-editor.py --serve    # serve only (used by the systemd unit)
    python3 bin/roadmap-editor.py --port N   # bind a different port (default 8765)
"""
from __future__ import annotations

import argparse
import hashlib
import html
import importlib.util
import io
import json
import os
import re
import socket
import sqlite3
import subprocess
import sys
import tempfile
import urllib.parse
import webbrowser
from contextlib import redirect_stderr
from datetime import datetime
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path
from zoneinfo import ZoneInfo

import yaml

REPO = Path(__file__).resolve().parent.parent
YAML_PATH = REPO / "roadmap.yaml"
GEN_PATH = REPO / "bin" / "gen-roadmap.py"
SERVER_ENV = REPO / "server.env"
# Published copy of the roadmap inside the generated wiki (docs/). Created by a
# full `nwn-manager wiki` build; Publish to Wiki swaps just its <main> body.
DOCS_ROADMAP = REPO / "docs" / "manual" / "Roadmap.html"
SRC_ROADMAP = REPO / "docs.manual" / "Roadmap.html"
# Standardized commit subject for editor-driven wiki publishes.
PUBLISH_COMMIT_MSG = "Roadmap: publish update via roadmap editor"

# Field order each idea is serialized in. Only `id/title/group/status` are
# required; the rest are emitted only when present.
FIELD_ORDER = ["id", "title", "group", "status", "type", "player", "date",
               "commit", "notes", "notes_h", "dupe_of"]
# Fields always rendered as YAML double-quoted scalars.
QUOTED_FIELDS = {"title", "notes", "date"}
# Players that aren't real people but are valid credits.
RESERVED_PLAYERS = ["community"]


def load_gen():
    """Import gen-roadmap.py (hyphenated name) to reuse STATUS + validate()."""
    spec = importlib.util.spec_from_file_location("gen_roadmap", GEN_PATH)
    mod = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(mod)
    return mod


GEN = load_gen()
STATUS = GEN.STATUS  # ordered dict: status -> {label, cls, board, rank}
TYPES = GEN.TYPES    # ordered dict: type -> {label, cls}
sanitize_notes = GEN.sanitize_notes  # whitelist sanitizer for idea `notes`


# --------------------------------------------------------------------------
# roadmap.yaml read / vocab
# --------------------------------------------------------------------------
def read_yaml() -> dict:
    return yaml.safe_load(YAML_PATH.read_text(encoding="utf-8")) or {}


def yaml_version() -> str:
    """Short content hash of roadmap.yaml — a version token the client rebases
    on. Any external edit (Claude, a hand-edit, another editor tab) changes it,
    which is how we detect a would-be clobber before writing. Missing file =>
    empty token."""
    try:
        return hashlib.sha256(YAML_PATH.read_bytes()).hexdigest()[:16]
    except OSError:
        return ""


def vocab(data: dict) -> dict:
    """Controlled vocabularies for the UI pickers, sourced from the file."""
    ideas = data.get("ideas", []) or []
    groups = [{"id": g["id"], "title": g["title"], "order": g.get("order")}
              for g in data.get("groups", [])]
    # Player picker = the managed roster, unioned with any name an idea already
    # uses (so a stray name is never silently dropped). `community` first.
    roster = [str(p) for p in (data.get("players", []) or [])]
    used = sorted({i["player"] for i in ideas if i.get("player")}, key=str.lower)
    names: list[str] = []
    for n in roster + used:
        if n and n not in names:
            names.append(n)
    players = ([p for p in RESERVED_PLAYERS if p in names]
               + [p for p in names if p not in RESERVED_PLAYERS])
    statuses = [{"id": k, "label": v["label"]} for k, v in STATUS.items()]
    types = [{"id": k, "label": v["label"]} for k, v in TYPES.items()]
    ids = [i.get("id") for i in ideas if i.get("id")]
    return {"groups": groups, "players": players, "statuses": statuses,
            "types": types, "ids": ids}


# --------------------------------------------------------------------------
# In-game merit database (read-only)
# --------------------------------------------------------------------------
# The live NWN server keeps merit totals + redemption requests in a campaign
# SQLite DB ("meritdb"). We read it strictly read-only to surface real in-game
# numbers next to the YAML-derived merit estimate. Earned merit is NOT stored;
# it is computed from the raw counters at these rates (mirrors merit_db.nss):
MERIT_RATE_BUG = 1       # Defect
MERIT_RATE_FEATURE = 2   # Enhancement
MERIT_RATE_EXPLOIT = 3   # Exploit


def merit_db_path() -> Path:
    """Filesystem path to the live meritdb campaign database."""
    home = os.environ.get("NWN_HOME_DIR") or os.path.join(
        os.path.expanduser("~"), ".local", "share", "Neverwinter Nights")
    return Path(home) / "database" / "meritdb.sqlite3"


def _merit_connect():
    """Open meritdb read-only, or return None if it can't be read."""
    db = merit_db_path()
    if not db.exists():
        return None
    con = sqlite3.connect(f"file:{db}?mode=ro", uri=True)
    con.row_factory = sqlite3.Row
    return con


def _name_candidates(roadmap_name: str) -> list[str]:
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


def _resolve_player_row(con, roadmap_name: str):
    """Smart-match a roadmap player name to a meritdb players row (or None)."""
    for cand in _name_candidates(roadmap_name):
        row = con.execute(
            "SELECT * FROM players WHERE name = ? COLLATE NOCASE LIMIT 1",
            (cand,)).fetchone()
        if row:
            return row
    return None


def merit_for_player(roadmap_name: str) -> dict:
    """Read-only in-game merit snapshot + spend history for one roadmap name."""
    con = _merit_connect()
    if con is None:
        return {"available": False,
                "reason": f"meritdb not found at {merit_db_path()}"}
    try:
        row = _resolve_player_row(con, roadmap_name)
        if row is None:
            return {"available": True, "matched": False,
                    "query": roadmap_name}
        bugs = row["bugs"] or 0
        exploits = row["exploits"] or 0
        features = row["features"] or 0
        spent = row["merit_spent"] or 0
        earned = (bugs * MERIT_RATE_BUG + features * MERIT_RATE_FEATURE
                  + exploits * MERIT_RATE_EXPLOIT)
        txns = [dict(r) for r in con.execute(
            "SELECT reward_label, reward_id, item_tag, cost, status, "
            "requested_at, resolved_at, needs_dm FROM redemptions "
            "WHERE cdkey = ? ORDER BY id DESC",
            (row["cdkey"],)).fetchall()]
        return {
            "available": True, "matched": True,
            "matched_name": row["name"], "last_login": row["last_login"],
            "bugs": bugs, "exploits": exploits, "features": features,
            "earned": earned, "spent": spent, "balance": earned - spent,
            "transactions": txns,
        }
    finally:
        con.close()


def pending_requests() -> dict:
    """Open DM-delivery merit requests (status='pending' AND needs_dm=1)."""
    con = _merit_connect()
    if con is None:
        return {"available": False, "count": 0, "rows": [],
                "reason": f"meritdb not found at {merit_db_path()}"}
    try:
        rows = [dict(r) for r in con.execute(
            "SELECT id, player_name, reward_label, cost, needs_dm, "
            "requested_at FROM redemptions "
            "WHERE status = 'pending' AND needs_dm = 1 "
            "ORDER BY requested_at").fetchall()]
        return {"available": True, "count": len(rows), "rows": rows}
    finally:
        con.close()


# --------------------------------------------------------------------------
# In-game "Recent Updates" sign DB (write)
# --------------------------------------------------------------------------
# The Well of Eru "Recent Updates" sign (tag recent_updates, conversation
# ru_sign, read by ru_db.nss) browses a campaign SQLite DB "roadmapdb". On
# Publish we refill its recent_updates table with the 10 most recently shipped
# ideas so the in-game board mirrors the website. The DB is NOT git-tracked
# (it lives under NWN_HOME_DIR); the live server picks up changes on next read.
SHIPPED_STATUSES = ("implemented", "awarded")
TYPE_PREFIX = {
    "Defect":      "Bug fixed: ",
    "Enhancement": "New feature: ",
    "Exploit":     "Exploit closed: ",
}
DEFAULT_PREFIX = "Update: "
_TAG_RE = re.compile(r"<[^>]+>")
_BLANKS_RE = re.compile(r"\n[ \t]*\n[ \t]*\n+")


def recent_db_path() -> Path:
    """Filesystem path to the live roadmapdb campaign database."""
    home = os.environ.get("NWN_HOME_DIR") or os.path.join(
        os.path.expanduser("~"), ".local", "share", "Neverwinter Nights")
    return Path(home) / "database" / "roadmapdb.sqlite3"


def html_to_plain(s: str) -> str:
    """Render an idea's `notes` HTML as NWN-readable plain text."""
    if not s:
        return ""
    t = s.replace("\r\n", "\n")
    t = re.sub(r"(?i)<\s*br\s*/?\s*>", "\n", t)        # <br> -> newline
    t = re.sub(r"(?i)<\s*li[^>]*>", "\n• ", t)    # <li> -> bullet
    t = re.sub(r"(?i)<\s*/\s*(div|p|li|ul|ol|h[1-6])\s*>", "\n", t)
    t = _TAG_RE.sub("", t)            # drop remaining tags, keep their text
    t = html.unescape(t)             # &amp; &lt; &#39; ...
    t = t.replace("\\n", "\n")       # any literal backslash-n in the source
    t = _BLANKS_RE.sub("\n\n", t)    # collapse 3+ newlines
    return "\n".join(ln.rstrip() for ln in t.split("\n")).strip()


def sync_recent_updates_db(ideas: list, groups: list | None) -> tuple[bool, str]:
    """Refill roadmapdb.recent_updates with the 10 most recently shipped ideas."""
    GEN.resolve_dates(ideas)  # explicit date wins; else derived from commit
    glabel = {g["id"]: html.unescape(g.get("title", g["id"]))
              for g in (groups or [])}
    shipped = [i for i in ideas
               if i.get("status") in SHIPPED_STATUSES and not i.get("dupe_of")]
    shipped.sort(key=lambda i: (i.get("date") or "", i.get("id") or ""),
                 reverse=True)

    rows = []
    for rank, idea in enumerate(shipped[:10]):
        player = idea.get("player") or ""
        if player == "community":
            player = "Community"
        rows.append((
            rank,
            idea.get("title") or "",
            TYPE_PREFIX.get(idea.get("type"), DEFAULT_PREFIX),
            glabel.get(idea.get("group"), idea.get("group") or ""),
            player,
            idea.get("date") or "",
            html_to_plain(idea.get("notes") or ""),
        ))

    db = recent_db_path()
    db.parent.mkdir(parents=True, exist_ok=True)
    con = sqlite3.connect(str(db))
    try:
        con.execute(
            "CREATE TABLE IF NOT EXISTS recent_updates ("
            "rank INTEGER PRIMARY KEY, title TEXT, prefix TEXT, "
            "group_label TEXT, player TEXT, date TEXT, notes TEXT)")
        con.execute("DELETE FROM recent_updates")
        con.executemany(
            "INSERT INTO recent_updates"
            "(rank,title,prefix,group_label,player,date,notes)"
            " VALUES(?,?,?,?,?,?,?)", rows)
        con.commit()
    finally:
        con.close()
    return True, f"synced {len(rows)} recent update(s) to {db.name}."


# --------------------------------------------------------------------------
# Comment-preserving write of the `ideas:` block
# --------------------------------------------------------------------------
ITEM_START = re.compile(r"^\s*-\s+id:\s*(\S+)")


def split_head_and_prefixes(text: str):
    """Return (head_text, {id: [prefix lines]}, [trailing lines]).

    head_text is everything up to and including the `ideas:` line, kept
    verbatim. Per-item prefixes are the comment/blank lines that precede each
    `- id:` item; trailing lines are comment/blank lines after the last item.
    """
    lines = text.splitlines()
    idx = next(i for i, ln in enumerate(lines) if re.match(r"^ideas:\s*$", ln))
    head = "\n".join(lines[: idx + 1]) + "\n"

    prefixes: dict[str, list[str]] = {}
    pending: list[str] = []
    last_id: str | None = None
    for ln in lines[idx + 1:]:
        m = ITEM_START.match(ln)
        if m:
            last_id = m.group(1)
            prefixes[last_id] = pending
            pending = []
        elif ln.strip() == "" or ln.lstrip().startswith("#"):
            pending.append(ln)
        # else: a body continuation line (title:, group:, ...) — skip; the body
        # is regenerated from the edited data, not preserved verbatim.
    trailing = pending
    return head, prefixes, trailing


def dquote(s: str) -> str:
    # notes now holds rich-text HTML that may span multiple lines; escape
    # newlines/tabs too so it stays a valid single-line double-quoted scalar.
    s = (s.replace("\\", "\\\\").replace('"', '\\"')
          .replace("\r", "\\r").replace("\n", "\\n").replace("\t", "\\t"))
    return '"' + s + '"'


def emit_scalar(field: str, value) -> str:
    s = str(value)
    if field in QUOTED_FIELDS:
        return dquote(s)
    if field == "player" and not re.fullmatch(r"[A-Za-z0-9_]+", s):
        return dquote(s)
    return s


def serialize_ideas(ideas: list[dict], prefixes: dict, trailing: list[str]) -> str:
    out: list[str] = []
    for idea in ideas:
        iid = idea.get("id", "")
        for pre in prefixes.get(iid, []):
            out.append(pre)
        first = True
        for field in FIELD_ORDER:
            val = idea.get(field)
            if val in (None, ""):
                continue
            scalar = emit_scalar(field, val)
            if first:
                out.append(f"  - {field}: {scalar}")
                first = False
            else:
                out.append(f"    {field}: {scalar}")
    out.extend(trailing)
    return "\n".join(out).rstrip("\n") + "\n"


TOP_KEY = re.compile(r"^[A-Za-z_][\w-]*:")


def replace_block(text: str, key: str, new_body: str) -> str:
    """Replace a top-level `key:` block's body, preserving everything else.

    Spans from the `key:` line to the next top-level key (or EOF). Trailing
    blank/comment lines inside the span belong to the *next* section's header,
    so they are kept; only the data rows are swapped for `new_body`.
    """
    lines = text.splitlines()
    start = next(i for i, ln in enumerate(lines)
                 if re.match(rf"^{re.escape(key)}:\s*$", ln))
    end = len(lines)
    for j in range(start + 1, len(lines)):
        if TOP_KEY.match(lines[j]):
            end = j
            break
    tail = end
    while tail - 1 > start and (lines[tail - 1].strip() == ""
                                or lines[tail - 1].lstrip().startswith("#")):
        tail -= 1
    new_lines = lines[:start + 1] + new_body.splitlines() + lines[tail:]
    return "\n".join(new_lines) + ("\n" if text.endswith("\n") else "")


def serialize_groups(groups: list[dict]) -> str:
    out: list[str] = []
    for g in groups:
        out.append(f"  - id: {g['id']}")
        out.append(f'    title: {dquote(str(g.get("title", "")))}')
        if g.get("order") not in (None, ""):
            out.append(f"    order: {g['order']}")
    return "\n".join(out)


def serialize_players(players: list[str]) -> str:
    out: list[str] = []
    for p in players:
        s = str(p)
        # Bare scalar is fine for plain names (incl. internal spaces); quote
        # only when YAML would otherwise mis-parse it.
        bare = re.fullmatch(r"[A-Za-z0-9_][A-Za-z0-9_ ]*", s)
        out.append(f"  - {s}" if bare else f"  - {dquote(s)}")
    return "\n".join(out)


def replace_ideas_block(text: str, ideas: list[dict]) -> str:
    """Rewrite the ideas block in `text` (it is the last top-level key)."""
    head, prefixes, trailing = split_head_and_prefixes(text)
    return head + serialize_ideas(ideas, prefixes, trailing)


def write_document(ideas: list[dict], groups: list[dict] | None = None,
                   players: list[str] | None = None) -> None:
    """Rewrite the ideas block, plus groups/players when supplied; everything
    else (meta/redemption/housing and all comments) is preserved verbatim."""
    text = YAML_PATH.read_text(encoding="utf-8")
    if groups is not None:
        text = replace_block(text, "groups", serialize_groups(groups))
    if players is not None:
        text = replace_block(text, "players", serialize_players(players))
    new_text = replace_ideas_block(text, ideas)
    fd, tmp = tempfile.mkstemp(dir=str(REPO), prefix=".roadmap.", suffix=".tmp")
    try:
        with os.fdopen(fd, "w", encoding="utf-8") as f:
            f.write(new_text)
        os.replace(tmp, YAML_PATH)
    except BaseException:
        if os.path.exists(tmp):
            os.unlink(tmp)
        raise


def extra_validate(groups, players) -> list[str]:
    """Structural checks for the editor-managed groups/players blocks."""
    errs: list[str] = []
    if groups is not None:
        seen = set()
        for g in groups:
            gid = g.get("id", "")
            if not re.fullmatch(r"[a-z0-9-]+", gid or ""):
                errs.append(f"group id '{gid}' must be lowercase letters/digits/hyphens")
            if gid in seen:
                errs.append(f"duplicate group id '{gid}'")
            seen.add(gid)
            if not str(g.get("title", "")).strip():
                errs.append(f"group '{gid}' needs a title")
    if players is not None:
        seen = set()
        for p in players:
            s = str(p).strip()
            if not s:
                errs.append("player roster has a blank name")
            if s in seen:
                errs.append(f"duplicate player '{s}'")
            seen.add(s)
    return errs


def validate_document(ideas, groups=None, players=None) -> tuple[list[str], list[str]]:
    """Run gen-roadmap's validate() plus our structural checks."""
    data = read_yaml()
    data["ideas"] = ideas
    if groups is not None:
        data["groups"] = groups
    if players is not None:
        data["players"] = players
    buf = io.StringIO()
    with redirect_stderr(buf):
        errors = GEN.validate(data)
    errors = list(errors) + extra_validate(groups, players)
    warnings = [ln.strip() for ln in buf.getvalue().splitlines() if ln.strip()]
    return errors, warnings


def regenerate() -> tuple[bool, str]:
    proc = subprocess.run(
        [sys.executable, str(GEN_PATH)],
        cwd=str(REPO), capture_output=True, text=True,
    )
    output = (proc.stdout + proc.stderr).strip()
    return proc.returncode == 0, output


# --------------------------------------------------------------------------
# "as of" timestamp — stamped on regenerate/publish in server-local time
# --------------------------------------------------------------------------
def server_tz() -> str:
    """Read TZ from server.env (e.g. 'America/Chicago'); default to it."""
    try:
        for ln in SERVER_ENV.read_text(encoding="utf-8").splitlines():
            m = re.match(r"\s*(?:export\s+)?TZ\s*=\s*(.+?)\s*$", ln)
            if m:
                return m.group(1).strip().strip('"').strip("'")
    except OSError:
        pass
    return "America/Chicago"


def now_stamp() -> str:
    """Current date + local time + zone abbrev, e.g. '2026-06-23 14:30 CDT'."""
    try:
        tz = ZoneInfo(server_tz())
    except Exception:
        tz = ZoneInfo("America/Chicago")
    return datetime.now(tz).strftime("%Y-%m-%d %H:%M %Z")


def stamp_as_of() -> str:
    """Rewrite the `as_of:` line inside the meta block to the current stamp,
    preserving everything else verbatim. Returns the stamp written."""
    text = YAML_PATH.read_text(encoding="utf-8")
    stamp = now_stamp()
    new_text, n = re.subn(
        r'^(\s*as_of:\s*).*$', rf'\g<1>"{stamp}"', text, count=1, flags=re.M)
    if n:
        fd, tmp = tempfile.mkstemp(dir=str(REPO), prefix=".roadmap.", suffix=".tmp")
        try:
            with os.fdopen(fd, "w", encoding="utf-8") as f:
                f.write(new_text)
            os.replace(tmp, YAML_PATH)
        except BaseException:
            if os.path.exists(tmp):
                os.unlink(tmp)
            raise
    return stamp


# --------------------------------------------------------------------------
# Publish to wiki: body-swap docs.manual/Roadmap.html into docs/manual/, then
# commit (roadmap.yaml + both Roadmap.html) and push.
# --------------------------------------------------------------------------
def publish_roadmap_to_docs() -> tuple[bool, str]:
    """Replicate nwn-wiki's manual-page publish for the roadmap alone: take the
    freshly generated source body and swap it into the already-published page's
    outer <main>, preserving the wiki header/footer/nav from the last full build.
    """
    if not DOCS_ROADMAP.exists():
        return False, (f"{DOCS_ROADMAP.relative_to(REPO)} does not exist — run a "
                       "full `nwn-manager wiki` build once before publishing.")
    src = SRC_ROADMAP.read_text(encoding="utf-8")
    m = re.search(r"<body[^>]*>(.*?)</body>", src, re.IGNORECASE | re.DOTALL)
    body = (m.group(1) if m else src).strip("\n")

    published = DOCS_ROADMAP.read_text(encoding="utf-8")
    # Greedy: <main> appears only in the body region, so this spans the first
    # <main> to the last </main> (the outer wiki <main>).
    swapped, n = re.subn(r"<main>.*</main>",
                         lambda _: f"<main>\n{body}\n  </main>",
                         published, count=1, flags=re.DOTALL)
    if not n:
        return False, "could not find <main> block in published Roadmap.html"
    DOCS_ROADMAP.write_text(swapped, encoding="utf-8")
    return True, f"published {DOCS_ROADMAP.relative_to(REPO)}"


def _git(*args: str) -> subprocess.CompletedProcess:
    return subprocess.run(["git", *args], cwd=str(REPO),
                          capture_output=True, text=True)


def git_publish() -> tuple[bool, str]:
    """Stage roadmap.yaml + both Roadmap.html, commit with the standard message,
    and push. 'Nothing to commit' is treated as success (nothing to publish)."""
    paths = ["roadmap.yaml", "docs.manual/Roadmap.html", "docs/manual/Roadmap.html"]
    add = _git("add", "--", *paths)
    if add.returncode != 0:
        return False, f"git add failed:\n{(add.stdout + add.stderr).strip()}"
    # Anything staged among our paths?
    staged = _git("diff", "--cached", "--quiet", "--", *paths)
    if staged.returncode == 0:
        return True, "nothing to commit — docs already up to date."
    commit = _git("commit", "-m", PUBLISH_COMMIT_MSG, "--", *paths)
    if commit.returncode != 0:
        return False, f"git commit failed:\n{(commit.stdout + commit.stderr).strip()}"
    push = _git("push")
    out = (commit.stdout + push.stdout + push.stderr).strip()
    if push.returncode != 0:
        return False, f"committed but push failed:\n{out}"
    return True, f"committed + pushed.\n{out}"


# --------------------------------------------------------------------------
# HTTP server
# --------------------------------------------------------------------------
class Handler(BaseHTTPRequestHandler):
    def log_message(self, *a):  # quiet
        pass

    def _send(self, code: int, body: bytes, ctype: str):
        self.send_response(code)
        self.send_header("Content-Type", ctype)
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        self.wfile.write(body)

    def _json(self, obj, code: int = 200):
        self._send(code, json.dumps(obj).encode("utf-8"), "application/json")

    def do_GET(self):
        if self.path == "/" or self.path.startswith("/index"):
            self._send(200, PAGE.encode("utf-8"), "text/html; charset=utf-8")
        elif self.path == "/api/data":
            data = read_yaml()
            self._json({"ideas": data.get("ideas", []) or [], "vocab": vocab(data),
                        "version": yaml_version()})
        elif self.path == "/api/version":
            self._json({"version": yaml_version()})
        elif self.path.startswith("/api/merit"):
            q = urllib.parse.urlparse(self.path).query
            player = urllib.parse.parse_qs(q).get("player", [""])[0]
            self._json(merit_for_player(player))
        elif self.path == "/api/pending":
            self._json(pending_requests())
        else:
            self._send(404, b"not found", "text/plain")

    def _read_body(self) -> dict:
        n = int(self.headers.get("Content-Length", 0))
        return json.loads(self.rfile.read(n) or b"{}")

    def do_POST(self):
        try:
            payload = self._read_body()
        except Exception as e:
            return self._json({"ok": False, "errors": [f"bad request: {e}"]}, 400)
        ideas = payload.get("ideas", [])
        groups = payload.get("groups")
        players = payload.get("players")
        base_version = payload.get("base_version")
        force = bool(payload.get("force"))
        # Anti-clobber: if the file changed on disk since the client loaded it
        # (external edit — Claude, a hand-edit, another tab) and the user hasn't
        # explicitly chosen Force, refuse the write so the external edit isn't
        # silently overwritten.
        if (base_version is not None and not force
                and base_version != yaml_version()):
            return self._json({
                "ok": False, "conflict": True, "version": yaml_version(),
                "message": ("roadmap.yaml changed on disk since you opened it "
                            "(external edit detected). Reload to pull those "
                            "changes, or Force save to overwrite them.")})
        if groups is not None:
            for g in groups:
                if str(g.get("order", "")).strip() != "":
                    try:
                        g["order"] = int(g["order"])
                    except (TypeError, ValueError):
                        pass
        for it in ideas:
            if str(it.get("notes_h", "")).strip() != "":
                try:
                    it["notes_h"] = int(float(it["notes_h"]))
                except (TypeError, ValueError):
                    it.pop("notes_h", None)
            # Strip any pasted chrome (e.g. Discord DOM) down to the whitelist
            # so the YAML — and every regenerate/publish from it — stays clean.
            if it.get("notes"):
                it["notes"] = sanitize_notes(it["notes"])
        errors, warnings = validate_document(ideas, groups, players)
        if errors:
            return self._json({"ok": False, "errors": errors, "warnings": warnings})

        if self.path == "/api/save":
            write_document(ideas, groups, players)
            return self._json({"ok": True, "warnings": warnings,
                               "version": yaml_version(),
                               "message": "Saved roadmap.yaml."})
        if self.path == "/api/regenerate":
            write_document(ideas, groups, players)
            stamp = stamp_as_of()
            ok, output = regenerate()
            return self._json({"ok": ok, "warnings": warnings, "output": output,
                               "version": yaml_version(),
                               "message": (f"Saved + regenerated Roadmap.html (as of {stamp})."
                                           if ok else "Regenerate FAILED.")})
        if self.path == "/api/publish":
            write_document(ideas, groups, players)
            stamp = stamp_as_of()
            steps: list[str] = [f"Stamped as of {stamp}."]
            ok, output = regenerate()
            if output:
                steps.append(output)
            if not ok:
                return self._json({"ok": False, "warnings": warnings,
                                   "version": yaml_version(),
                                   "output": "\n".join(steps),
                                   "message": "Regenerate FAILED — not published."})
            pub_ok, pub_msg = publish_roadmap_to_docs()
            steps.append(pub_msg)
            if not pub_ok:
                return self._json({"ok": False, "warnings": warnings,
                                   "version": yaml_version(),
                                   "output": "\n".join(steps),
                                   "message": "Publish FAILED."})
            # Sync the in-game Recent Updates sign DB. Non-fatal: a DB failure
            # must never block the wiki publish/push.
            try:
                _, db_msg = sync_recent_updates_db(ideas, groups)
            except Exception as e:
                db_msg = f"DB sync FAILED (wiki still published): {e}"
            steps.append(db_msg)
            git_ok, git_msg = git_publish()
            steps.append(git_msg)
            return self._json({"ok": git_ok, "warnings": warnings,
                               "version": yaml_version(),
                               "output": "\n".join(steps),
                               "message": ("Published to wiki + pushed to git."
                                           if git_ok else "Publish/push FAILED.")})
        return self._json({"ok": False, "errors": ["unknown endpoint"]}, 404)


# --------------------------------------------------------------------------
# Browser UI (single inline page, no build step, no external deps)
# --------------------------------------------------------------------------
PAGE = r"""<!doctype html>
<html lang="en"><head><meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<title>Roadmap / Merit Backlog Editor</title>
<style>
  :root { --bg:#1e2127; --panel:#272b33; --ink:#e6e6e6; --mut:#9aa3af;
          --line:#3a3f4a; --accent:#6ea8fe; --warn:#e6b800; --err:#ff6b6b;
          --ok:#5cd6a0; }
  * { box-sizing:border-box; }
  body { margin:0; font:14px/1.45 system-ui,sans-serif; background:var(--bg);
         color:var(--ink); display:flex; height:100vh; }
  h1 { font-size:15px; margin:0 0 8px; }
  #left { width:380px; min-width:300px; border-right:1px solid var(--line);
          display:flex; flex-direction:column; }
  #right { flex:1; padding:16px 20px; overflow:auto; }
  .pad { padding:12px 14px; }
  #filter { width:100%; padding:7px 9px; background:var(--panel); color:var(--ink);
            border:1px solid var(--line); border-radius:6px; }
  #list { overflow:auto; flex:1; }
  .row { padding:8px 14px; border-bottom:1px solid var(--line); cursor:pointer; }
  .row:hover { background:#2d323b; }
  .row.sel { background:#33405a; }
  .row .t { display:block; }
  .row .meta { color:var(--mut); font-size:12px; }
  .badge { display:inline-block; padding:1px 7px; border-radius:10px; font-size:11px;
           background:#3a3f4a; color:#cfd6e0; }
  .badge.shipped,.badge.awarded { background:#26543f; color:#bdf0d6; }
  .badge.wip { background:#3a4a66; color:#cfe0ff; }
  .badge.soon { background:#34405c; color:#c4d3f0; }
  .badge.later { background:#3c4150; color:#c7cdde; }
  .badge.planned { background:#4a4636; color:#f0e6bd; }
  .badge.unlikely { background:#33363d; color:#9aa3af; }
  .badge.confirmed,.badge.implemented { background:#503a4f; color:#f0cfe6; }
  .tbadge { display:inline-block; padding:1px 7px; border-radius:10px; font-size:11px;
            border:1px solid transparent; }
  .tbadge.defect      { background:#4a2626; color:#f0b8b8; border-color:#7a3a3a; }
  .tbadge.enhancement { background:#23364f; color:#b8d2f0; border-color:#36567a; }
  .tbadge.exploit     { background:#3c2a4f; color:#d8b8f0; border-color:#5c3a7a; }
  label { display:block; margin:10px 0 3px; color:var(--mut); font-size:12px; }
  input,select,textarea { width:100%; padding:7px 9px; background:var(--panel);
           color:var(--ink); border:1px solid var(--line); border-radius:6px;
           font:inherit; }
  textarea { min-height:64px; resize:vertical; }
  /* Rich-text notes widget */
  .tabs { display:flex; gap:4px; margin:10px 0 0; }
  .tab { padding:5px 12px; font-size:12px; background:var(--panel); color:var(--mut);
         border:1px solid var(--line); border-bottom:none; border-radius:6px 6px 0 0;
         cursor:pointer; width:auto; }
  .tab.active { color:var(--ink); background:#2d323b; border-color:var(--accent); }
  .rt-wrap { border:1px solid var(--line); border-radius:0 6px 6px 6px; padding:8px;
             background:var(--panel); }
  .rt-tools { display:flex; flex-wrap:wrap; gap:4px; align-items:center;
              margin-bottom:7px; }
  .rt-tools button { padding:3px 9px; font-size:13px; line-height:1; width:auto;
                     min-width:30px; }
  .rt-tools .sep { width:1px; align-self:stretch; background:var(--line); margin:0 3px; }
  .rt-tools input[type=color] { width:30px; height:26px; padding:1px; cursor:pointer; }
  #f_notes_rich { min-height:128px; height:128px; overflow:auto; resize:vertical;
                  padding:7px 9px; background:var(--bg); color:var(--ink);
                  border:1px solid var(--line); border-radius:6px; outline:none; }
  #f_notes_rich:focus { border-color:var(--accent); }
  #f_notes_rich ul, #f_notes_rich ol { margin:0.3em 0; padding-left:1.5em; }
  #f_notes_rich a { color:var(--accent); }
  #f_notes_html { min-height:128px; height:128px; font-family:monospace; font-size:12px; }
  .grid2 { display:grid; grid-template-columns:1fr 1fr; gap:0 14px; }
  button { padding:8px 13px; border:1px solid var(--line); border-radius:6px;
           background:var(--panel); color:var(--ink); cursor:pointer; font:inherit; }
  button:hover { border-color:var(--accent); }
  button.primary { background:var(--accent); color:#10161f; border-color:var(--accent);
                   font-weight:600; }
  button.danger { color:var(--err); }
  .bar { display:flex; gap:8px; flex-wrap:wrap; margin-top:14px; }
  .spacer { flex:1; }
  #banner { margin:10px 0; padding:9px 11px; border-radius:6px; display:none;
            white-space:pre-wrap; }
  #banner.ok { display:block; background:#193a2b; color:var(--ok);
               border:1px solid #2c6b4e; }
  #banner.bad { display:block; background:#3a1d1d; color:var(--err);
               border:1px solid #6b2c2c; }
  #banner.warn { display:block; background:#3a3417; color:var(--warn);
               border:1px solid #6b5e2c; }
  .hint { color:var(--warn); font-size:12px; margin-top:3px; min-height:14px; }
  .small { color:var(--mut); font-size:12px; }
  .filters { display:grid; grid-template-columns:1fr 1fr; gap:6px; margin-top:8px; }
  .filters select { padding:5px 7px; font-size:12px; }
  .filters .full { grid-column:1 / -1; }
  .chk { display:flex; align-items:center; gap:6px; margin-top:8px; font-size:12px;
         color:var(--mut); cursor:pointer; }
  .chk input { width:auto; }
  .linkbtn { background:none; border:none; color:var(--accent); cursor:pointer;
             padding:0; font:inherit; font-size:12px; }
  .modal-bg { position:fixed; inset:0; background:rgba(0,0,0,0.55); display:none;
              align-items:flex-start; justify-content:center; padding:6vh 16px; z-index:9; }
  .modal-bg.show { display:flex; }
  .modal { background:var(--panel); border:1px solid var(--line); border-radius:8px;
           width:min(560px,100%); max-height:86vh; overflow:auto; padding:16px 18px; }
  .modal h2 { margin:0 0 10px; }
  .mlist { border:1px solid var(--line); border-radius:6px; overflow:hidden; margin:8px 0; }
  .mrow { display:flex; gap:8px; align-items:center; padding:6px 8px;
          border-bottom:1px solid var(--line); }
  .mrow:last-child { border-bottom:none; }
  .mrow input { flex:1; }
  .mrow input.ord { flex:0 0 64px; }
  .mrow .gid { flex:0 0 130px; color:var(--mut); font-size:12px; font-family:monospace;
               white-space:nowrap; overflow:hidden; text-overflow:ellipsis; }
  .mrow .use { flex:0 0 auto; color:var(--mut); font-size:11px; }
  .merit { margin-top:18px; padding:11px 13px; border:1px solid var(--line);
           border-radius:8px; background:#23272f; }
  .merit h3 { margin:0 0 8px; font-size:13px; color:var(--ink); }
  .merit .who { color:var(--accent); }
  .merit .counts { display:flex; gap:8px; flex-wrap:wrap; align-items:center; }
  .merit .pts { margin-top:9px; font-size:13px; }
  .merit .pts b { font-size:16px; color:var(--ok); }
  .merit .note { color:var(--warn); font-size:11px; margin-top:6px; }
  .merit .sub { color:var(--mut); font-size:11px; margin-top:6px; }
  .merit .bal { color:var(--accent); }
  .merit .muted { color:var(--mut); }
  .txns { width:100%; border-collapse:collapse; margin-top:9px; font-size:12px; }
  .txns th, .txns td { text-align:left; padding:3px 6px; border-bottom:1px solid var(--line); }
  .txns th { color:var(--mut); font-weight:600; }
  .txns td.cost { text-align:right; color:var(--err); font-variant-numeric:tabular-nums; }
  .txns .st { font-size:11px; }
  .txns .st.pending { color:var(--warn); }
  .txns .st.fulfilled { color:var(--ok); }
  .txns .st.cancelled { color:var(--mut); text-decoration:line-through; }
  #mpending.has { color:var(--warn); font-weight:600; }
  /* header external links */
  .extlinks { display:flex; gap:12px; margin:2px 0 8px; }
  .extlinks a { color:var(--accent); font-size:12px; text-decoration:none; }
  .extlinks a:hover { text-decoration:underline; }
  /* view toggle */
  .viewtoggle { display:flex; gap:4px; margin:0 0 8px; }
  .viewtoggle button { padding:4px 12px; font-size:12px; width:auto; }
  .viewtoggle button.on { background:var(--accent); color:#10161f;
                          border-color:var(--accent); font-weight:600; }
  /* kanban board */
  #board { display:flex; gap:10px; height:100%; align-items:stretch;
           overflow-x:auto; overflow-y:hidden; padding-bottom:6px; }
  .lane { flex:0 0 230px; display:flex; flex-direction:column; min-width:0;
          background:var(--panel); border:1px solid var(--line); border-radius:8px; }
  .lane-h { padding:8px 10px; border-bottom:1px solid var(--line); font-size:12px;
            font-weight:600; display:flex; align-items:center; gap:6px; }
  .lane-h .n { color:var(--mut); font-weight:400; }
  .lane-cards { flex:1; overflow-y:auto; padding:8px; display:flex;
                flex-direction:column; gap:8px; }
  .lane.drop { border-color:var(--accent); }
  .lane.drop .lane-cards { background:#2a3040; }
  .card { background:var(--bg); border:1px solid var(--line); border-radius:6px;
          padding:8px 9px; cursor:pointer; }
  .card:hover { border-color:var(--accent); }
  .card.dragging { opacity:0.45; }
  .card .ct { display:block; font-size:13px; margin-bottom:5px; }
  .card .cmeta { color:var(--mut); font-size:11px; display:block; margin-bottom:6px; }
  .card select { padding:3px 5px; font-size:11px; }
</style></head>
<body>
<div id="left">
  <div class="pad">
    <h1>Roadmap / Merit Backlog</h1>
    <div class="extlinks">
      <a href="https://homerslotr.com/" target="_blank" rel="noopener">Public wiki ↗</a>
      <a href="https://homerslotr.com/manual/Roadmap" target="_blank" rel="noopener">Public roadmap ↗</a>
    </div>
    <div class="viewtoggle">
      <button id="view_board" class="on">Board</button>
      <button id="view_list">List</button>
    </div>
    <label class="chk"><input type="checkbox" id="f_carddd">
      Card status dropdowns (Board)</label>
    <input id="filter" placeholder="search title, player, group, status…">
    <div class="filters">
      <select id="f_fstatus"><option value="">All statuses</option></select>
      <select id="f_ftype"><option value="">All types</option></select>
      <select id="f_fplayer"><option value="">All players</option></select>
      <select id="f_fgroup"><option value="">All groups</option></select>
      <select id="f_sort">
        <option value="status">Sort: status</option>
        <option value="group">Sort: group</option>
        <option value="player">Sort: player</option>
        <option value="date">Sort: date (newest)</option>
        <option value="title">Sort: title</option>
        <option value="file">Sort: file order</option>
      </select>
    </div>
    <label class="chk"><input type="checkbox" id="f_showawarded">
      Show awarded (done) ideas</label>
    <div class="bar">
      <button id="add">+ Add idea</button>
      <button id="mgroups" class="linkbtn">Manage groups</button>
      <button id="mplayers" class="linkbtn">Manage players</button>
      <button id="mpending" class="linkbtn">Pending Merit Requests</button>
      <span class="spacer"></span>
      <span id="count" class="small"></span>
    </div>
  </div>
  <div id="list"></div>
</div>
<div id="right">
  <div id="banner"></div>
  <div id="form"></div>
</div>
<div class="modal-bg" id="modal"><div class="modal" id="modalbox"></div></div>
<script>
let DATA = {ideas:[], vocab:{groups:[],players:[],statuses:[],ids:[]}};
let sel = -1;
let baseVersion = null;      // hash of roadmap.yaml as we last loaded/saved it
let view = 'board';          // 'list' | 'board' — Board is the default view
let showCardDropdown = false; // per-card status <select> on board cards (off by default)
// Board lanes, left→right = pipeline flow. Labels come from DATA.vocab.statuses
// (sourced from gen-roadmap.py STATUS) so they never drift.
const BOARD_LANES = ['planned','later','soon','wip','confirmed',
                     'implemented','awarded','unlikely'];
// Sentinel filter value: match rows whose field is empty/unset.
const BLANK = '__BLANK__';
const BLANK_OPT = `<option value="${BLANK}">&lt;Is Blank&gt;</option>`;
const $ = s => document.querySelector(s);

function statusCls(s){ return s || ''; }
function typeCls(t){ return (t||'').toLowerCase(); }
function esc(s){ return (s||'').replace(/[&<>"]/g, c => (
  {'&':'&amp;','<':'&lt;','>':'&gt;','"':'&quot;'}[c])); }

function groupTitle(id){
  const g = DATA.vocab.groups.find(g=>g.id===id);
  return g ? g.title.replace(/&amp;/g,'&') : (id||'—');
}

async function load(){
  const r = await fetch('/api/data'); DATA = await r.json();
  baseVersion = DATA.version || null;
  populateFilters();
  if (view==='board'){ const f=$('#form'); if (f) f.style.display='none'; renderBoard(); }
  else { renderList(); if (DATA.ideas.length) select(0); }
  refreshPending();
}

// Update the "X Pending Merit Requests" button label from the live game DB.
function refreshPending(){
  const btn=$('#mpending'); if(!btn) return;
  fetch('/api/pending').then(r=>r.json()).then(d=>{
    const n=d.count||0;
    btn.textContent=`${n} Pending Merit Request${n===1?'':'s'}`;
    btn.classList.toggle('has', n>0);
  }).catch(()=>{});
}

function populateFilters(){
  const sSel=$('#f_fstatus'), tSel=$('#f_ftype'), pSel=$('#f_fplayer'), gSel=$('#f_fgroup');
  const sCur=sSel.value, tCur=tSel.value, pCur=pSel.value, gCur=gSel.value;
  sSel.innerHTML='<option value="">All statuses</option>'+
    DATA.vocab.statuses.map(s=>`<option value="${esc(s.id)}">${esc(s.id)} — ${esc(s.label)}</option>`).join('');
  tSel.innerHTML='<option value="">All types</option>'+
    (DATA.vocab.types||[]).map(t=>`<option value="${esc(t.id)}">${esc(t.label)}</option>`).join('')+
    BLANK_OPT;
  pSel.innerHTML='<option value="">All players</option>'+BLANK_OPT+
    DATA.vocab.players.map(p=>`<option value="${esc(p)}">${esc(p)}</option>`).join('');
  gSel.innerHTML='<option value="">All groups</option>'+
    DATA.vocab.groups.map(g=>`<option value="${esc(g.id)}">${esc(groupTitle(g.id))}</option>`).join('');
  sSel.value=sCur; tSel.value=tCur; pSel.value=pCur; gSel.value=gCur;
}

function statusRank(s){
  const i = DATA.vocab.statuses.findIndex(x=>x.id===s);
  return i<0 ? 999 : i;
}

function visibleRows(){
  const q = $('#filter').value.toLowerCase();
  const fs=$('#f_fstatus').value, ft=$('#f_ftype').value;
  const fp=$('#f_fplayer').value, fg=$('#f_fgroup').value;
  // Board always shows the awarded lane; the "Show awarded" checkbox only
  // governs the list view.
  const showAwarded=(view==='board') || $('#f_showawarded').checked, sort=$('#f_sort').value;
  let rows = DATA.ideas.map((it,idx)=>({it,idx})).filter(({it})=>{
    if (!showAwarded && it.status==='awarded') return false;
    if (fs && it.status!==fs) return false;
    if (ft){ if (ft===BLANK){ if (it.type) return false; } else if ((it.type||'')!==ft) return false; }
    if (fp){ if (fp===BLANK){ if (it.player) return false; } else if ((it.player||'')!==fp) return false; }
    if (fg && it.group!==fg) return false;
    if (q){
      const hay=[it.title,it.player,it.group,it.status,it.type,it.id].join(' ').toLowerCase();
      if(!hay.includes(q)) return false;
    }
    return true;
  });
  const cmp = {
    status:(a,b)=> statusRank(a.it.status)-statusRank(b.it.status) || (a.it.title||'').localeCompare(b.it.title||''),
    group: (a,b)=> (groupTitle(a.it.group)).localeCompare(groupTitle(b.it.group)) || statusRank(a.it.status)-statusRank(b.it.status),
    player:(a,b)=> (a.it.player||'~~').toLowerCase().localeCompare((b.it.player||'~~').toLowerCase()) || (a.it.title||'').localeCompare(b.it.title||''),
    date:  (a,b)=> (b.it.date||'').localeCompare(a.it.date||''),
    title: (a,b)=> (a.it.title||'').localeCompare(b.it.title||''),
    file:  (a,b)=> a.idx-b.idx,
  }[sort] || ((a,b)=>a.idx-b.idx);
  rows.sort(cmp);
  return rows;
}

function renderList(){
  const rows = visibleRows();
  const box=$('#list'); box.innerHTML='';
  rows.forEach(({it,idx})=>{
    const d=document.createElement('div');
    d.className='row'+(idx===sel?' sel':'');
    const tbadge = it.type
      ? `<span class="tbadge ${typeCls(it.type)}">${esc(it.type)}</span> ` : '';
    d.innerHTML=`<span class="t">${esc(it.title||'(untitled)')}</span>
      <span class="meta">${tbadge}<span class="badge ${statusCls(it.status)}">${esc(it.status||'?')}</span>
      ${esc(groupTitle(it.group))}${it.player?' · '+esc(it.player):''}</span>`;
    d.onclick=()=>select(idx);
    box.appendChild(d);
  });
  $('#count').textContent=`${rows.length}/${DATA.ideas.length} ideas`;
}

// Re-render whichever view is active (filters/search call this).
function render(){ if (view==='board') renderBoard(); else renderList(); }

function setView(v){
  view = v;
  $('#view_list').classList.toggle('on', v==='list');
  $('#view_board').classList.toggle('on', v==='board');
  const right=$('#right'), form=$('#form');
  if (v==='board'){
    if (form) form.style.display='none';
    renderBoard();
  } else {
    let b=$('#board'); if (b) b.remove();
    if (form) form.style.display='';
    renderList();
    if (sel>=0 && DATA.ideas[sel]) select(sel); else if (DATA.ideas.length) select(0);
  }
}

function statusLabel(id){
  const s=(DATA.vocab.statuses||[]).find(x=>x.id===id);
  return s ? s.label : id;
}

let dragIdx = -1;   // idea index currently being dragged across lanes

function renderBoard(){
  const rows = visibleRows();
  const buckets={}; BOARD_LANES.forEach(s=>buckets[s]=[]);
  rows.forEach(({it,idx})=>{ if (buckets[it.status]) buckets[it.status].push({it,idx}); });

  let board=$('#board');
  if (!board){ board=document.createElement('div'); board.id='board'; $('#right').appendChild(board); }
  board.innerHTML = BOARD_LANES.map(s=>{
    const cards = buckets[s].map(({it,idx})=>{
      const tbadge = it.type
        ? `<span class="tbadge ${typeCls(it.type)}">${esc(it.type)}</span> ` : '';
      const ddHtml = showCardDropdown
        ? `<select class="cst" data-idx="${idx}">${BOARD_LANES.map(ls=>
            `<option value="${esc(ls)}"${ls===it.status?' selected':''}>${esc(statusLabel(ls))}</option>`).join('')}</select>`
        : '';
      return `<div class="card" draggable="true" data-idx="${idx}">
        <span class="ct">${esc(it.title||'(untitled)')}</span>
        <span class="cmeta">${tbadge}${esc(groupTitle(it.group))}${it.player?' · '+esc(it.player):''}</span>
        ${ddHtml}
      </div>`;
    }).join('');
    return `<div class="lane" data-status="${esc(s)}">
      <div class="lane-h">${esc(statusLabel(s))} <span class="n">${buckets[s].length}</span></div>
      <div class="lane-cards">${cards}</div>
    </div>`;
  }).join('');
  $('#count').textContent=`${rows.length}/${DATA.ideas.length} ideas`;

  // Card click → open the edit form (switches back to list view). The status
  // dropdown must not trigger this.
  board.querySelectorAll('.card').forEach(c=>{
    c.onclick=e=>{ if (e.target.closest('.cst')) return;
      const idx=+c.dataset.idx; setView('list'); select(idx); };
    c.ondragstart=e=>{ dragIdx=+c.dataset.idx; c.classList.add('dragging');
      e.dataTransfer.effectAllowed='move'; };
    c.ondragend=()=>{ c.classList.remove('dragging'); dragIdx=-1; };
  });
  // Per-card status dropdown fallback.
  board.querySelectorAll('.cst').forEach(sel0=>{
    sel0.onclick=e=>e.stopPropagation();
    sel0.onchange=e=>moveToStatus(+sel0.dataset.idx, e.target.value);
  });
  // Lane drop targets.
  board.querySelectorAll('.lane').forEach(lane=>{
    lane.ondragover=e=>{ e.preventDefault(); e.dataTransfer.dropEffect='move';
      lane.classList.add('drop'); };
    lane.ondragleave=()=>lane.classList.remove('drop');
    lane.ondrop=e=>{ e.preventDefault(); lane.classList.remove('drop');
      if (dragIdx>=0) moveToStatus(dragIdx, lane.dataset.status); };
  });
}

// Change one idea's status (drag drop or dropdown) and persist via Save.
function moveToStatus(idx, status){
  const it=DATA.ideas[idx];
  if (!it || it.status===status) return;
  it.status=status;
  renderBoard();
  commit('/api/save');
}

function opt(value,label,cur){
  return `<option value="${esc(value)}"${value===cur?' selected':''}>${esc(label)}</option>`;
}

function select(i){
  sel = i; renderList();
  const it = DATA.ideas[i]; if (!it) { $('#form').innerHTML=''; return; }
  const groups = DATA.vocab.groups.map(g=>opt(g.id, g.title.replace(/&amp;/g,'&'), it.group)).join('');
  const stats  = DATA.vocab.statuses.map(s=>opt(s.id, s.id+' — '+s.label, it.status)).join('');
  const types  = ['<option value=""></option>'].concat(
      (DATA.vocab.types||[]).map(t=>opt(t.id, t.label, it.type||''))).join('');
  const players = ['<option value=""></option>'].concat(
      DATA.vocab.players.map(p=>opt(p,p,it.player||''))).join('');
  const dupes = ['<option value=""></option>'].concat(
      DATA.vocab.ids.filter(id=>id!==it.id).map(id=>opt(id,id,it.dupe_of||''))).join('');
  $('#form').innerHTML = `
    <label>Title (this IS the public one-line description)</label>
    <input id="f_title" value="${esc(it.title)}">
    <div class="grid2">
      <div><label>Group</label><select id="f_group">${groups}</select></div>
      <div><label>Status</label><select id="f_status">${stats}</select></div>
    </div>
    <div class="grid2">
      <div><label>Type (Defect / Enhancement / Exploit)</label>
        <select id="f_type">${types}</select></div>
      <div></div>
    </div>
    <div class="grid2">
      <div>
        <label>Player (submitter credit)</label>
        <input id="f_player" list="players_dl" value="${esc(it.player||'')}"
               placeholder="(none / admin)">
        <datalist id="players_dl">${players}</datalist>
        <div class="hint" id="player_hint"></div>
      </div>
      <div><label>Duplicate of (merges credit)</label>
        <select id="f_dupe">${dupes}</select></div>
    </div>
    <div class="grid2">
      <div><label>Date (shown on page)</label>
        <input id="f_date" type="date" value="${esc(it.date||'')}"></div>
      <div><label>Commit (optional git ref)</label>
        <input id="f_commit" value="${esc(it.commit||'')}"></div>
    </div>
    <label>id (stable key; lowercase-hyphen)</label>
    <input id="f_id" value="${esc(it.id||'')}">
    <label>Notes (extra detail, optional)</label>
    <div class="tabs">
      <button type="button" class="tab active" id="tab_rich" data-tab="rich">Rich text</button>
      <button type="button" class="tab" id="tab_html" data-tab="html">HTML</button>
    </div>
    <div class="rt-wrap">
      <div class="rt-tools" id="rt_tools">
        <button type="button" data-cmd="bold" title="Bold"><b>B</b></button>
        <button type="button" data-cmd="italic" title="Italic"><i>I</i></button>
        <button type="button" data-cmd="underline" title="Underline"><u>U</u></button>
        <span class="sep"></span>
        <button type="button" data-cmd="insertUnorderedList" title="Bullet list">&bull; List</button>
        <button type="button" data-cmd="insertOrderedList" title="Numbered list">1. List</button>
        <span class="sep"></span>
        <input type="color" id="rt_color" value="#6ea8fe" title="Font color">
        <span class="sep"></span>
        <button type="button" id="rt_link" title="Link to another idea">&#128279; Idea</button>
        <button type="button" id="rt_extlink" title="Insert web link">&#128279; URL</button>
        <button type="button" data-cmd="removeFormat" title="Clear formatting">Clear</button>
      </div>
      <div id="f_notes_rich" contenteditable="true"></div>
      <textarea id="f_notes_html" style="display:none"></textarea>
    </div>
    <div class="bar">
      <button class="primary" id="save">Save</button>
      <button id="regen">Save &amp; regenerate HTML</button>
      <button id="publish">Publish to Wiki &amp; DB</button>
      <span class="spacer"></span>
      <button class="danger" id="del">Delete</button>
    </div>
    <p class="small">Order in this list = order in the file. Use the buttons to move.</p>
    <div class="bar">
      <button id="up">↑ Move up</button>
      <button id="down">↓ Move down</button>
    </div>
    <div id="merit"></div>
    <div id="merit_ingame"></div>`;
  bindPlayerHint();
  initNotes(it);
  renderMerit(it.player||'');
  renderMeritIngame(it.player||'');
  $('#f_player').addEventListener('input', e=>{
    const v=e.target.value.trim();
    renderMerit(v); renderMeritIngame(v);
  });
  $('#save').onclick = ()=>commit('/api/save');
  $('#regen').onclick = ()=>commit('/api/regenerate');
  $('#publish').onclick = ()=>{
    if(!confirm('Regenerate, publish the roadmap into docs/, sync the in-game Recent Updates DB, commit & git push?')) return;
    commit('/api/publish');
  };
  $('#del').onclick = del;
  $('#up').onclick = ()=>move(-1);
  $('#down').onclick = ()=>move(1);
}

// Lifetime merit for a submitter: count their *awarded* (totally done) ideas by
// type and weight them Defect=1, Enhancement=2, Exploit=3.
const MERIT_POINTS = {Defect:1, Enhancement:2, Exploit:3};
function playerMerit(name){
  const c={Defect:0, Enhancement:0, Exploit:0}; let untyped=0;
  DATA.ideas.forEach(it=>{
    if(it.status!=='awarded' || (it.player||'')!==name) return;
    if(c[it.type]!=null) c[it.type]++; else untyped++;
  });
  const total=c.Defect*MERIT_POINTS.Defect + c.Enhancement*MERIT_POINTS.Enhancement
            + c.Exploit*MERIT_POINTS.Exploit;
  return {c, untyped, total};
}

function renderMerit(name){
  const box=$('#merit'); if(!box) return;
  if(!name){ box.innerHTML=''; return; }
  const {c, untyped, total}=playerMerit(name);
  const awarded=c.Defect+c.Enhancement+c.Exploit;
  const chip=(t,n)=>`<span class="tbadge ${t.toLowerCase()}">${t}: ${n}</span>`;
  const note = untyped>0
    ? `<div class="note">${untyped} awarded item(s) for this player have no type set — not counted.</div>` : '';
  box.innerHTML=`<div class="merit">
    <h3>Lifetime merit — <span class="who">${esc(name)}</span></h3>
    <div class="counts">${chip('Defect',c.Defect)} ${chip('Enhancement',c.Enhancement)} ${chip('Exploit',c.Exploit)}</div>
    <div class="pts">Total awarded points: <b>${total}</b></div>
    <div class="sub">${awarded} awarded idea(s) · Defect=1, Enhancement=2, Exploit=3.</div>
    ${note}
  </div>`;
}

// Real in-game merit for a player, read live (read-only) from the game's
// meritdb. Earned is computed from raw counters (Defect=1, Enhancement=2,
// Exploit=3); spend history comes from the redemptions table. Tracks the
// pending fetch so a fast typist doesn't get a stale earlier response.
let meritReq = 0;
function renderMeritIngame(name){
  const box=$('#merit_ingame'); if(!box) return;
  if(!name){ box.innerHTML=''; return; }
  const my = ++meritReq;
  box.innerHTML=`<div class="merit"><div class="sub">Loading in-game merit…</div></div>`;
  fetch('/api/merit?player='+encodeURIComponent(name))
    .then(r=>r.json())
    .then(d=>{
      if(my!==meritReq) return;  // a newer request superseded this one
      if(!d.available){
        box.innerHTML=`<div class="merit"><h3>In-game merit</h3>
          <div class="note">${esc(d.reason||'in-game database unavailable')}</div></div>`;
        return;
      }
      if(!d.matched){
        box.innerHTML=`<div class="merit"><h3>In-game merit — <span class="who">${esc(name)}</span></h3>
          <div class="note">No in-game record found for this player name.</div>
          <div class="sub">Name is matched against the account login name in meritdb.</div></div>`;
        return;
      }
      const chip=(t,n)=>`<span class="tbadge ${t.toLowerCase()}">${t}: ${n}</span>`;
      const txns=(d.transactions||[]);
      const rows=txns.map(t=>{
        const when=(t.requested_at||'').slice(0,10);
        const st=(t.status||'').toLowerCase();
        return `<tr>
          <td>${esc(t.reward_label||('#'+(t.reward_id||'?')))}</td>
          <td class="muted">${esc(t.item_tag||'')}</td>
          <td class="cost">${t.cost}</td>
          <td><span class="st ${st}">${esc(t.status||'')}</span></td>
          <td class="muted">${esc(when)}</td>
        </tr>`;
      }).join('');
      const table = txns.length ? `<table class="txns">
        <tr><th>Reward</th><th>Tag</th><th style="text-align:right">Cost</th><th>Status</th><th>When</th></tr>
        ${rows}</table>`
        : `<div class="sub">No merit-spending transactions.</div>`;
      box.innerHTML=`<div class="merit">
        <h3>In-game merit — <span class="who">${esc(d.matched_name)}</span></h3>
        <div class="counts">${chip('Defect',d.bugs)} ${chip('Enhancement',d.features)} ${chip('Exploit',d.exploits)}</div>
        <div class="pts">Earned: <b>${d.earned}</b> · Spent: ${d.spent} · Available: <b class="bal">${d.balance}</b></div>
        <div class="sub">Live from meritdb (account-wide). Defect=1, Enhancement=2, Exploit=3.</div>
        ${table}
      </div>`;
    })
    .catch(e=>{
      if(my!==meritReq) return;
      box.innerHTML=`<div class="merit"><h3>In-game merit</h3>
        <div class="note">Could not load in-game merit: ${esc(String(e))}</div></div>`;
    });
}

// ---- rich-text notes widget ---------------------------------------------
const NOTES_DEFAULT_H = 128;       // px; double the old textarea min-height
let notesTab = 'rich';             // which view is active for the current idea
let savedRange = null;             // selection saved before opening the link picker

function notesVisibleEl(){
  return notesTab==='html' ? $('#f_notes_html') : $('#f_notes_rich');
}

// Treat an editor that holds no real text and no block/inline content as empty,
// so blank notes don't serialize a stray "<br>" into roadmap.yaml.
function normalizeNotes(html){
  const tmp=document.createElement('div'); tmp.innerHTML=html||'';
  if (tmp.textContent.trim()==='' && !/<(ul|ol|li|img|a|hr|table)/i.test(html||''))
    return '';
  return (html||'').trim();
}

function initNotes(it){
  const rich=$('#f_notes_rich'), html=$('#f_notes_html');
  notesTab='rich';
  rich.innerHTML = it.notes || '';
  html.value = it.notes || '';
  const h = (it.notes_h && it.notes_h>0) ? it.notes_h : NOTES_DEFAULT_H;
  rich.style.height = h+'px'; html.style.height = h+'px';
  rich.style.display=''; html.style.display='none';
  $('#tab_rich').classList.add('active'); $('#tab_html').classList.remove('active');

  $('#tab_rich').onclick=()=>switchNotes('rich');
  $('#tab_html').onclick=()=>switchNotes('html');
  $('#rt_tools').querySelectorAll('button[data-cmd]').forEach(b=>{
    b.onmousedown=e=>e.preventDefault();            // keep the editor's selection
    b.onclick=()=>{ rich.focus(); document.execCommand(b.dataset.cmd, false, null); };
  });
  const col=$('#rt_color');
  col.onmousedown=()=>{ saveRange(); };
  col.oninput=()=>{ rich.focus(); restoreRange();
    document.execCommand('foreColor', false, col.value); };
  const lb=$('#rt_link');
  lb.onmousedown=e=>{ e.preventDefault(); saveRange(); };
  lb.onclick=openIdeaLink;
  const xb=$('#rt_extlink');
  xb.onmousedown=e=>{ e.preventDefault(); saveRange(); };
  xb.onclick=openExtLink;

  // Strip pasted chrome (e.g. Discord's whole message DOM) to the same whitelist
  // the Python sanitizer enforces, so it never enters the editor in the first
  // place. Python remains the authoritative backstop on save.
  rich.addEventListener('paste', e=>{
    e.preventDefault();
    const cb=e.clipboardData||window.clipboardData;
    const htmlData=cb && cb.getData('text/html');
    const cleaned = htmlData
      ? cleanPastedHTML(htmlData)
      : esc((cb && cb.getData('text/plain'))||'');
    rich.focus();
    document.execCommand('insertHTML', false, cleaned);
  });
}

// Allowed tags / per-tag attrs — mirrors bin/roadmap_sanitize.py.
const PASTE_TAGS = new Set(['A','B','STRONG','I','EM','U','UL','OL','LI',
  'P','BR','HR','DIV','SPAN','FONT','IMG','BLOCKQUOTE']);
const PASTE_ATTRS = {A:['href','target','rel'], FONT:['color'],
  IMG:['src','alt','width','height']};

function cleanPastedHTML(html){
  const tmpl=document.createElement('template');
  tmpl.innerHTML = html||'';
  const walk = node => {
    const out=[];
    node.childNodes.forEach(ch=>{
      if (ch.nodeType===3){ out.push(esc(ch.nodeValue)); return; }   // text
      if (ch.nodeType!==1) return;                                   // skip comments etc.
      const tag=ch.tagName;
      const inner=walk(ch);
      if (!PASTE_TAGS.has(tag)){ out.push(inner); return; }          // unwrap
      const allow=PASTE_ATTRS[tag]||[];
      let attrs='';
      allow.forEach(a=>{
        let v=ch.getAttribute(a); if(v==null) return; v=v.trim();
        if (a==='href' && !(v.startsWith('#')||/^(https?:|mailto:)/i.test(v))) return;
        if (a==='src'  && !/^https?:/i.test(v)) return;
        attrs += ' '+a+'="'+esc(v).replace(/"/g,'&quot;')+'"';
      });
      if (tag==='BR'||tag==='HR'||tag==='IMG') out.push('<'+tag.toLowerCase()+attrs+'>');
      else out.push('<'+tag.toLowerCase()+attrs+'>'+inner+'</'+tag.toLowerCase()+'>');
    });
    return out.join('');
  };
  return walk(tmpl.content);
}

function switchNotes(to){
  const rich=$('#f_notes_rich'), html=$('#f_notes_html');
  if (to===notesTab) return;
  const curH = notesVisibleEl().offsetHeight;
  if (to==='html'){ html.value = rich.innerHTML; }
  else { rich.innerHTML = html.value; }
  notesTab=to;
  rich.style.display = to==='rich'?'':'none';
  html.style.display = to==='html'?'':'none';
  notesVisibleEl().style.height = curH+'px';        // carry the height across views
  $('#tab_rich').classList.toggle('active', to==='rich');
  $('#tab_html').classList.toggle('active', to==='html');
}

function saveRange(){
  const s=window.getSelection();
  savedRange = (s && s.rangeCount) ? s.getRangeAt(0).cloneRange() : null;
}
function restoreRange(){
  if(!savedRange) return;
  const s=window.getSelection(); s.removeAllRanges(); s.addRange(savedRange);
}

function openIdeaLink(){
  const ids = DATA.vocab.ids.filter(id=>id!==(DATA.ideas[sel]||{}).id);
  const rows = ids.map(id=>{
    const t = (DATA.ideas.find(i=>i.id===id)||{}).title || '';
    return `<div class="mrow" style="cursor:pointer" data-id="${esc(id)}">
      <span class="gid" title="${esc(id)}">${esc(id)}</span>
      <span style="flex:1;color:var(--mut);overflow:hidden;text-overflow:ellipsis;white-space:nowrap">${esc(t)}</span>
    </div>`;}).join('');
  modalHTML(`<h2>Link to another idea</h2>
    <p class="small">Pick an idea — a link is inserted that jumps to it on the
      published page. Selected text becomes the link label (otherwise the idea title).</p>
    <input id="ilink_f" placeholder="filter ideas…" style="margin-bottom:8px">
    <div class="mlist" id="ilink_rows" style="max-height:48vh;overflow:auto">${rows}</div>
    <div class="bar"><span class="spacer"></span><button id="ilink_close">Cancel</button></div>`);
  const apply=id=>{
    const t=(DATA.ideas.find(i=>i.id===id)||{}).title || id;
    const sel0 = savedRange && savedRange.toString();
    const label = (sel0 && sel0.trim()) ? sel0 : t;
    const link = `<a href="#idea-${id}">${esc(label)}</a>`;
    closeModal();
    if (notesTab==='html'){
      const ta=$('#f_notes_html');
      const a=ta.selectionStart, b=ta.selectionEnd;
      ta.value = ta.value.slice(0,a) + link + ta.value.slice(b);
      ta.focus(); ta.selectionStart=ta.selectionEnd=a+link.length;
    } else {
      $('#f_notes_rich').focus(); restoreRange();
      document.execCommand('insertHTML', false, link);
    }
  };
  $('#ilink_close').onclick=closeModal;
  const filt=$('#ilink_f');
  filt.oninput=()=>{ const q=filt.value.toLowerCase();
    document.querySelectorAll('#ilink_rows .mrow').forEach(r=>{
      r.style.display = r.textContent.toLowerCase().includes(q)?'':'none'; }); };
  document.querySelectorAll('#ilink_rows .mrow').forEach(r=>
    r.onclick=()=>apply(r.dataset.id));
}

// Insert raw HTML at the saved caret in whichever notes tab is active.
function insertIntoNotes(html){
  if (notesTab==='html'){
    const ta=$('#f_notes_html');
    const a=ta.selectionStart, b=ta.selectionEnd;
    ta.value = ta.value.slice(0,a) + html + ta.value.slice(b);
    ta.focus(); ta.selectionStart=ta.selectionEnd=a+html.length;
  } else {
    $('#f_notes_rich').focus(); restoreRange();
    document.execCommand('insertHTML', false, html);
  }
}

function openExtLink(){
  const selText = (savedRange && savedRange.toString().trim()) || '';
  modalHTML(`<h2>Insert web link</h2>
    <p class="small">Adds an external link that opens in a new tab. Leave the text
      blank to use the selected text, or the URL itself.</p>
    <label class="small">URL</label>
    <input id="xlink_url" placeholder="https://example.com" style="margin-bottom:8px">
    <label class="small">Link text</label>
    <input id="xlink_txt" placeholder="${esc(selText) || 'link text'}" style="margin-bottom:8px">
    <div class="bar"><span class="spacer"></span>
      <button id="xlink_close">Cancel</button>
      <button id="xlink_ok" class="primary">Insert</button></div>`);
  const apply=()=>{
    let url=$('#xlink_url').value.trim();
    if (!url) return;
    // Normalize so the notes sanitizer (http/https/mailto/# only) accepts it.
    if (!url.startsWith('#') && !/^(https?:|mailto:)/i.test(url)) url='https://'+url;
    const label = $('#xlink_txt').value.trim() || selText || url;
    const link = `<a href="${esc(url).replace(/"/g,'&quot;')}" target="_blank" rel="noopener">${esc(label)}</a>`;
    closeModal();
    insertIntoNotes(link);
  };
  $('#xlink_close').onclick=closeModal;
  $('#xlink_ok').onclick=apply;
  const u=$('#xlink_url');
  u.onkeydown=e=>{ if(e.key==='Enter'){ e.preventDefault(); apply(); } };
  u.focus();
}

function bindPlayerHint(){
  const inp = $('#f_player'); const hint = $('#player_hint');
  const known = new Set(DATA.vocab.players);
  const check = ()=>{
    const v = inp.value.trim();
    hint.textContent = (v && !known.has(v))
      ? `“${v}” is not a known submitter — typo? (saving will still work)` : '';
  };
  inp.oninput = check; check();
}

function readForm(){
  // Canonical notes = the active view's content; keep the views in sync first.
  const rich=$('#f_notes_rich'), html=$('#f_notes_html');
  const raw = notesTab==='html' ? html.value : rich.innerHTML;
  const notes = normalizeNotes(raw);
  const notes_h = Math.round(notesVisibleEl().offsetHeight);
  return {
    id: $('#f_id').value.trim(),
    title: $('#f_title').value.trim(),
    group: $('#f_group').value,
    status: $('#f_status').value,
    type: $('#f_type').value,
    player: $('#f_player').value.trim(),
    date: $('#f_date').value.trim(),
    commit: $('#f_commit').value.trim(),
    notes: notes,
    notes_h: (notes && notes_h && notes_h!==NOTES_DEFAULT_H) ? notes_h : '',
    dupe_of: $('#f_dupe').value,
  };
}

function pruneEmpty(o){
  const r={}; for (const k of ['id','title','group','status','type','player','date','commit','notes','notes_h','dupe_of'])
    if (o[k]!=='' && o[k]!=null) r[k]=o[k];
  return r;
}

function banner(cls,msg){ const b=$('#banner'); b.className=cls; b.textContent=msg; }

async function commit(endpoint, force){
  // Capture where we are in the *visible* (filtered + sorted) list so we can
  // advance to the next item there after the save reloads from the file, even
  // if the edit moved or dropped the current item out of the view.
  let nextId=null, curPos=-1;
  // In list view, fold the open form's edits into DATA before sending. In board
  // view there is no live form, so skip this (moveToStatus already mutated the
  // idea in place).
  if (view==='list' && sel>=0 && $('#f_id')){
    // Capture the next row from the list *as currently displayed*, BEFORE the
    // edit is applied — otherwise an edit that changes a sort key (status,
    // group, title…) re-sorts the current item and "next" is taken relative to
    // its new position, making the selection jump somewhere unexpected.
    const vis = visibleRows();
    curPos = vis.findIndex(r=>r.idx===sel);
    if (curPos>=0 && curPos+1<vis.length) nextId = vis[curPos+1].it.id;
    DATA.ideas[sel] = pruneEmpty(readForm());
  }
  const r = await fetch(endpoint, {method:'POST',
    headers:{'Content-Type':'application/json'},
    body: JSON.stringify({ideas: DATA.ideas, groups: DATA.vocab.groups,
                          players: DATA.vocab.players,
                          base_version: baseVersion, force: !!force})});
  const res = await r.json();
  if (res.version) baseVersion = res.version;   // rebase our baseline
  if (res.conflict){ conflictBanner(endpoint); return; }
  if (!res.ok){
    banner('bad', 'Not saved:\n• ' + (res.errors||['unknown error']).join('\n• ')
      + (res.warnings&&res.warnings.length ? '\n\nWarnings:\n• '+res.warnings.join('\n• '):''));
    return;
  }
  let msg = res.message || 'Saved.';
  if (res.warnings && res.warnings.length) msg += '\n\nWarnings:\n• '+res.warnings.join('\n• ');
  if (res.output) msg += '\n\n'+res.output;
  banner(res.warnings&&res.warnings.length ? 'warn':'ok', msg);
  await load();
  if (view==='list') advanceSelection(nextId, curPos);
}

// External-edit conflict: the file changed on disk since we loaded it. Offer to
// Reload the latest (losing in-page edits) or Force-overwrite it.
function conflictBanner(endpoint){
  const b=$('#banner'); b.className='warn';
  b.innerHTML='';
  const msg=document.createElement('div');
  msg.textContent='⚠ roadmap.yaml changed on disk since you opened it '
    +'(external edit detected). Reload to pull those changes, or Force save to overwrite them.';
  const bar=document.createElement('div'); bar.className='bar';
  const reload=document.createElement('button'); reload.textContent='Reload latest';
  reload.onclick=()=>{ b.className=''; b.textContent=''; load(); };
  const forceb=document.createElement('button'); forceb.className='danger';
  forceb.textContent='Force save (overwrite)';
  forceb.onclick=()=>commit(endpoint, true);
  bar.appendChild(reload); bar.appendChild(forceb);
  b.appendChild(msg); b.appendChild(bar);
}

function advanceSelection(nextId, curPos){
  const vis = visibleRows();
  let target = -1;
  // Prefer the item that followed the one we just edited.
  if (nextId){ const r = vis.find(x=>x.it.id===nextId); if (r) target = r.idx; }
  // Otherwise hold the same slot in the (possibly shorter) visible list.
  if (target<0 && curPos>=0 && vis.length) target = vis[Math.min(curPos, vis.length-1)].idx;
  if (target>=0){ select(target); }
  else { sel=-1; renderList(); $('#form').innerHTML=''; }
}

function move(dir){
  if (sel<0) return;
  DATA.ideas[sel] = pruneEmpty(readForm());
  const j = sel+dir; if (j<0||j>=DATA.ideas.length) return;
  [DATA.ideas[sel],DATA.ideas[j]]=[DATA.ideas[j],DATA.ideas[sel]];
  sel=j; renderList(); select(sel);
}

function del(){
  if (sel<0) return;
  if (!confirm('Delete this idea from the backlog?')) return;
  DATA.ideas.splice(sel,1);
  sel = Math.min(sel, DATA.ideas.length-1);
  renderList(); if (sel>=0) select(sel); else $('#form').innerHTML='';
  banner('warn','Deleted in the editor. Click Save to write it to roadmap.yaml.');
}

$('#add').onclick = ()=>{
  const g = DATA.vocab.groups[0] ? DATA.vocab.groups[0].id : '';
  DATA.ideas.unshift({id:'', title:'', group:g, status:'planned'});
  // Adding needs the full form (id + title), so always land in list view.
  if (view!=='list'){ setView('list'); }
  sel=0; renderList(); select(0);
  banner('warn','New idea added. Give it a unique id + title, then Save.');
};

// ---- group / player management modals -----------------------------------
const escAmp = s => s.replace(/&/g,'&amp;');          // store titles in YAML form
const dispAmp = s => (s||'').replace(/&amp;/g,'&');   // ...show them un-escaped
function modalHTML(html){ $('#modalbox').innerHTML=html; $('#modal').classList.add('show'); }
function closeModal(){ $('#modal').classList.remove('show'); }
$('#modal').onclick = e=>{ if(e.target.id==='modal') closeModal(); };

function openGroups(){
  const rows = DATA.vocab.groups.map((g,i)=>`
    <div class="mrow" data-i="${i}">
      <span class="gid" title="${esc(g.id)}">${esc(g.id)}</span>
      <input class="gt" value="${esc(dispAmp(g.title))}">
      <input class="ord" type="number" value="${g.order==null?'':g.order}">
      <span class="use">${DATA.ideas.filter(it=>it.group===g.id).length}</span>
    </div>`).join('');
  modalHTML(`<h2>Manage groups</h2>
    <p class="small">Rename a title or change its order. The <b>id</b> is the stable key
      ideas reference — it can't be changed here. The number is how many ideas use it.</p>
    <div class="mlist" id="grows">${rows}</div>
    <h3 style="font-size:13px;margin:12px 0 4px;">Add a group</h3>
    <div class="mrow">
      <input id="ng_id" class="gid" style="flex:0 0 150px;" placeholder="id (lowercase-hyphen)">
      <input id="ng_title" placeholder="Title (shown on the page)">
      <input id="ng_order" class="ord" type="number" placeholder="ord">
      <button id="ng_add">Add</button>
    </div>
    <div class="hint" id="g_hint"></div>
    <div class="bar"><button class="primary" id="g_save">Save changes</button>
      <span class="spacer"></span><button id="g_close">Close</button></div>`);
  $('#ng_add').onclick=()=>{
    const id=$('#ng_id').value.trim(), title=$('#ng_title').value.trim();
    const ord=$('#ng_order').value.trim();
    if(!/^[a-z0-9-]+$/.test(id)){ $('#g_hint').textContent='id must be lowercase letters/digits/hyphens'; return; }
    if(DATA.vocab.groups.some(g=>g.id===id)){ $('#g_hint').textContent='that id already exists'; return; }
    if(!title){ $('#g_hint').textContent='give the group a title'; return; }
    DATA.vocab.groups.push({id, title:escAmp(title), order: ord===''?null:parseInt(ord,10)});
    openGroups();
  };
  $('#g_save').onclick=()=>{
    document.querySelectorAll('#grows .mrow').forEach(row=>{
      const g=DATA.vocab.groups[+row.dataset.i];
      g.title=escAmp(row.querySelector('.gt').value.trim());
      const o=row.querySelector('.ord').value.trim();
      g.order = o===''?null:parseInt(o,10);
    });
    commit('/api/save'); closeModal();
  };
  $('#g_close').onclick=closeModal;
}

function openPlayers(){
  const rows = DATA.vocab.players.map((p,i)=>{
    const n = DATA.ideas.filter(it=>it.player===p).length;
    const reserved = p==='community';
    return `<div class="mrow" data-orig="${esc(p)}">
      <input class="pn" value="${esc(p)}" ${reserved?'disabled':''}>
      <span class="use">${n} ideas</span>
      ${reserved?'<span class="use">(reserved)</span>':'<button class="linkbtn pdel">remove</button>'}
    </div>`;}).join('');
  modalHTML(`<h2>Manage players</h2>
    <p class="small">Rename a submitter and it updates every idea credited to them.
      Add a name below to pre-register someone before they have an idea.</p>
    <div class="mlist" id="prows">${rows}</div>
    <h3 style="font-size:13px;margin:12px 0 4px;">Add a player</h3>
    <div class="mrow"><input id="np_name" placeholder="Submitter name">
      <button id="np_add">Add</button></div>
    <div class="hint" id="p_hint"></div>
    <div class="bar"><button class="primary" id="p_save">Save changes</button>
      <span class="spacer"></span><button id="p_close">Close</button></div>`);
  $('#np_add').onclick=()=>{
    const n=$('#np_name').value.trim();
    if(!n) return;
    if(DATA.vocab.players.includes(n)){ $('#p_hint').textContent='already in the roster'; return; }
    DATA.vocab.players.push(n); openPlayers();
  };
  document.querySelectorAll('#prows .pdel').forEach(b=>b.onclick=()=>{
    const orig=b.closest('.mrow').dataset.orig;
    const n=DATA.ideas.filter(it=>it.player===orig).length;
    if(n>0){ $('#p_hint').textContent=`“${orig}” is used by ${n} idea(s) — rename or reassign first`; return; }
    DATA.vocab.players=DATA.vocab.players.filter(x=>x!==orig); openPlayers();
  });
  $('#p_save').onclick=()=>{
    const names=[];
    for(const row of document.querySelectorAll('#prows .mrow')){
      const orig=row.dataset.orig, inp=row.querySelector('.pn');
      const val=inp.disabled?orig:inp.value.trim();
      if(!val){ $('#p_hint').textContent='names cannot be blank'; return; }
      if(val!==orig) DATA.ideas.forEach(it=>{ if(it.player===orig) it.player=val; });
      names.push(val);
    }
    if(new Set(names).size!==names.length){ $('#p_hint').textContent='two rows ended up with the same name'; return; }
    DATA.vocab.players=names;
    commit('/api/save'); closeModal();
  };
  $('#p_close').onclick=closeModal;
}

// ---- pending DM-delivery merit requests (read-only) ---------------------
function openPending(){
  modalHTML(`<h2>Pending Merit Requests</h2>
    <p class="small">Loading open DM-delivery requests…</p>`);
  fetch('/api/pending').then(r=>r.json()).then(d=>{
    refreshPending();
    if(!d.available){
      modalHTML(`<h2>Pending Merit Requests</h2>
        <p class="hint">${esc(d.reason||'in-game database unavailable')}</p>
        <div class="bar"><span class="spacer"></span><button id="pr_close">Close</button></div>`);
      $('#pr_close').onclick=closeModal; return;
    }
    const rows=(d.rows||[]).map(t=>{
      const when=(t.requested_at||'').slice(0,16).replace('T',' ');
      return `<tr>
        <td class="muted">#${t.id}</td>
        <td>${esc(t.player_name||'')}</td>
        <td>${esc(t.reward_label||'')}</td>
        <td class="cost">${t.cost}</td>
        <td class="muted">${esc(when)}</td>
      </tr>`;
    }).join('');
    const body = d.count
      ? `<table class="txns">
          <tr><th>ID</th><th>Player</th><th>Reward</th><th style="text-align:right">Cost</th><th>Requested</th></tr>
          ${rows}</table>`
      : `<p class="small">No open DM-delivery requests. 🎉</p>`;
    modalHTML(`<h2>${d.count} Pending Merit Request${d.count===1?'':'s'}</h2>
      <p class="small">Open requests awaiting DM delivery (status=pending, needs a DM).
        Read-only — fulfil/cancel them in game.</p>
      ${body}
      <div class="bar"><span class="spacer"></span><button id="pr_close">Close</button></div>`);
    $('#pr_close').onclick=closeModal;
  }).catch(e=>{
    modalHTML(`<h2>Pending Merit Requests</h2>
      <p class="hint">Could not load: ${esc(String(e))}</p>
      <div class="bar"><span class="spacer"></span><button id="pr_close">Close</button></div>`);
    $('#pr_close').onclick=closeModal;
  });
}

['f_fstatus','f_ftype','f_fplayer','f_fgroup','f_sort'].forEach(id=>$('#'+id).onchange=render);
$('#f_showawarded').onchange=render;
$('#mgroups').onclick=openGroups;
$('#mplayers').onclick=openPlayers;
$('#mpending').onclick=openPending;
$('#filter').oninput = render;
$('#view_list').onclick=()=>setView('list');
$('#view_board').onclick=()=>setView('board');
$('#f_carddd').onchange=e=>{ showCardDropdown=e.target.checked;
  if (view==='board') renderBoard(); };

// Background poll: notice an external edit (Claude, hand-edit, another tab) and
// warn passively. Paused while a modal is open, and never clobbers a live
// conflict banner. The Save/Force flow is the hard guard; this is just a nudge.
setInterval(async ()=>{
  if ($('#modal').classList.contains('show')) return;
  try{
    const d=await (await fetch('/api/version')).json();
    if (d.version && baseVersion && d.version!==baseVersion){
      const b=$('#banner');
      if (!b.querySelector('button')){   // don't stomp an active conflict banner
        banner('warn','⚠ roadmap.yaml changed on disk (external edit) — Reload '
          +'to see it. Your next Save will warn before overwriting.');
      }
    }
  }catch(e){}
}, 15000);

load();
</script>
</body></html>
"""


def main():
    ap = argparse.ArgumentParser(description="Local web editor for roadmap.yaml ideas.")
    ap.add_argument("--port", type=int, default=8765)
    ap.add_argument("--host", default="0.0.0.0",
                    help="bind address (default 0.0.0.0 = reachable from any LAN device; "
                         "use 127.0.0.1 to restrict to this machine)")
    ap.add_argument("--serve", action="store_true",
                    help="serve without opening a browser (used by the systemd unit)")
    args = ap.parse_args()

    httpd = ThreadingHTTPServer((args.host, args.port), Handler)
    url = f"http://localhost:{args.port}/"
    print(f"Roadmap editor serving on {args.host}:{args.port}  (editing {YAML_PATH})")
    if args.host == "0.0.0.0":
        try:
            host = socket.gethostname()
            ip = socket.gethostbyname(host)
            print(f"  LAN access: http://{host}:{args.port}/  or  http://{ip}:{args.port}/")
        except Exception:
            pass
        print("  (bound to all interfaces, no auth — trusts your local network)")
    if not args.serve:
        try:
            webbrowser.open(url)
        except Exception:
            pass
    try:
        httpd.serve_forever()
    except KeyboardInterrupt:
        print("\nbye")


if __name__ == "__main__":
    main()
