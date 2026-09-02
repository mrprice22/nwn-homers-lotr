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
import contextlib
import copy
import fcntl
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
import threading
import time
import traceback
import urllib.parse
import webbrowser
from contextlib import redirect_stderr
from datetime import datetime
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path
from zoneinfo import ZoneInfo

import yaml

sys.path.insert(0, str(Path(__file__).resolve().parent))
import roadmap_auth as AUTH   # noqa: E402  (path set up immediately above)
import roadmap_merit as MERIT   # noqa: E402  (meritdb access, shared with the CLI)

REPO = Path(__file__).resolve().parent.parent
YAML_PATH = REPO / "roadmap.yaml"
GEN_PATH = REPO / "bin" / "gen-roadmap.py"
PUBLISH_PATH = REPO / "bin" / "roadmap_publish.py"
# Palette Finder: standalone map of blueprint -> toolset-palette location. Built
# on demand by bin/gen-palette-map.py (the "Refresh palette map" button); never
# part of the wiki build. module-index/ is gitignored, so it may not exist yet.
PALETTE_GEN_PATH = REPO / "bin" / "gen-palette-map.py"
PALETTE_MAP_PATH = REPO / "module-index" / "palette_map.json"
SERVER_ENV = REPO / "server.env"
# Published copy of the roadmap inside the generated wiki (docs/). Created by a
# full `nwn-manager wiki` build; Publish to Wiki swaps just its <main> body.
DOCS_ROADMAP = REPO / "docs" / "manual" / "Roadmap.html"
SRC_ROADMAP = REPO / "docs.manual" / "Roadmap.html"
# Standardized commit subject for editor-driven wiki publishes.
PUBLISH_COMMIT_MSG = "Roadmap: publish update via roadmap editor"

# Field order each idea is serialized in. Only `id/title/group/status` are
# required; the rest are emitted only when present.
FIELD_ORDER = ["id", "title", "group", "epic", "status", "hidden",
               "merit_awarded", "type",
               "player", "date", "commit", "notes", "notes_h", "impl_notes",
               "impl_notes_h", "dupe_of", "design_questions", "manual_steps",
               "uat_credits", "comments"]
# `merit_awarded` records that meritdb was really credited for this idea, which
# `status: awarded` alone cannot: status can bounce back to `implemented` and
# forward again, and the merit must be granted exactly once. Written only by the
# Award / Revoke buttons in the detail-pane header bar (never by the form, the
# status dropdown, or a board-lane drag) — see award_merit().
MERIT_FLAG = "merit_awarded"
# Internal fields — admin-only, never rendered on the public board. `notes` is
# the player-facing release note; everything here is the builder's own record.
LIST_FIELDS = {"design_questions", "manual_steps", "uat_credits", "comments"}
# Players credited with validating this idea's fix — one merit each, awarded
# independently of who reported it, so several players can appear on one item.
# `awarded: true` is the same kind of idempotence flag as MERIT_FLAG: it records
# that meritdb was really credited, and is written ONLY by the UAT award button.
UAT_FIELD = "uat_credits"
# Append-only per-idea notes: {author, date, text}. A tester has no `edit`, so
# this is how they add information to an item at all -- and append-only is what
# keeps that safe: there is no route that rewrites or deletes an entry, so the
# worst a tester can do to the record is add to it. Internal like the rest of
# LIST_FIELDS; nothing on the public page or the in-game sign renders it.
COMMENTS_FIELD = "comments"
INTERNAL_FIELDS = LIST_FIELDS | {"impl_notes", "impl_notes_h"}
# Fields always rendered as YAML double-quoted scalars.
QUOTED_FIELDS = {"title", "notes", "impl_notes", "date"}
# Workflow states for a manual step. `done` is the only terminal state; only a
# non-done step with blocker=True gates the autopilot (see CLAUDE-autopilot.md).
# `failed` records a check that WAS run and did not pass — it is an *open* state
# everywhere downstream (the wiki, the in-game sign, release notes and
# open_blockers() all test `status == "done"` and negate it), so it is visible
# only inside this editor. See CLAUDE-roadmap.md.
STEP_STATUS = ("open", "wip", "failed", "done")
# Persisted pixel heights of the vertically-resizable text boxes. Each is
# emitted only when the box was resized away from its default.
HEIGHT_KEYS = ("notes_h", "impl_notes_h", "step_h", "question_h", "answer_h")
# Players that aren't real people but are valid credits.
RESERVED_PLAYERS = ["community"]


def load_gen():
    """Import gen-roadmap.py (hyphenated name) to reuse STATUS + validate()."""
    spec = importlib.util.spec_from_file_location("gen_roadmap", GEN_PATH)
    mod = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(mod)
    return mod


def load_publish():
    """Import bin/roadmap_publish.py — the roadmapdb (in-game sign) writer."""
    spec = importlib.util.spec_from_file_location("roadmap_publish", PUBLISH_PATH)
    mod = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(mod)
    return mod


def load_review():
    """Import bin/llm/review_api.py — the LLM change-ledger review panel.

    Optional on purpose: the harness under bin/llm/ is a separate concern, and
    the editor must still start on a checkout where nothing has ever been
    generated. A failure here disables the panel, never the editor.
    """
    try:
        bindir = str(Path(__file__).resolve().parent)
        if bindir not in sys.path:
            sys.path.insert(0, bindir)
        from llm import review_api  # noqa: PLC0415
        return review_api
    except Exception as exc:  # noqa: BLE001
        print(f"[warn] LLM review panel unavailable: {exc}", file=sys.stderr)
        return None


GEN = load_gen()
PUB = load_publish()
REVIEW = load_review()
# FIELD_ORDER orders the same names gen-roadmap.py validates against. A field
# added to one and not the other means either a silently unrendered key or a
# spurious "unrecognised field" warning, so say so loudly at startup.
_drift = set(FIELD_ORDER) ^ GEN.IDEA_FIELDS
if _drift:
    print(f"[warn] FIELD_ORDER and gen-roadmap.py IDEA_FIELDS disagree on: "
          f"{sorted(_drift)}", file=sys.stderr)
STATUS = GEN.STATUS  # ordered dict: status -> {label, cls, board, rank}
TYPES = GEN.TYPES    # ordered dict: type -> {label, cls}
sanitize_notes = GEN.sanitize_notes  # whitelist sanitizer for idea `notes`


# --------------------------------------------------------------------------
# roadmap.yaml read / vocab
# --------------------------------------------------------------------------
# PyYAML's pure-Python SafeLoader parses this file in ~2.0 s; libyaml's
# CSafeLoader does the same job in ~0.17 s. A save used to parse twice, which is
# most of where the old 5-6 s save went. Fall back if libyaml isn't compiled in.
try:
    from yaml import CSafeLoader as _YamlLoader
except ImportError:                                  # pragma: no cover
    from yaml import SafeLoader as _YamlLoader

# Parsed-document cache, keyed on the file's identity+mtime+size. Callers mutate
# what they get back (validate_document overlays the posted blocks), so every
# hit hands out a deep copy — the cache holds the pristine parse.
_YAML_CACHE: dict = {"key": None, "doc": None}


def _yaml_key():
    try:
        st = YAML_PATH.stat()
    except OSError:
        return None
    return (st.st_ino, st.st_mtime_ns, st.st_size)


def read_yaml() -> dict:
    """Parse roadmap.yaml, reusing the last parse while the file is untouched."""
    key = _yaml_key()
    if key is not None and _YAML_CACHE["key"] == key:
        return copy.deepcopy(_YAML_CACHE["doc"])
    doc = yaml.load(YAML_PATH.read_text(encoding="utf-8"), Loader=_YamlLoader) or {}
    # Re-stat: if the file moved under us mid-read, don't cache a torn parse.
    if key is not None and _yaml_key() == key:
        _YAML_CACHE["key"], _YAML_CACHE["doc"] = key, copy.deepcopy(doc)
    return doc


# --------------------------------------------------------------------------
# Per-idea fingerprints — the basis of the three-way merge
# --------------------------------------------------------------------------
# The whole-file version token below can only answer "did anything change?".
# That made every external edit — Claude touching one unrelated item — invalidate
# the admin's entire in-page session: the conflict banner's only offers were
# "Reload" (lose your edits) or "Force" (lose Claude's). Fingerprinting each idea
# lets a save that touched *different* ids merge cleanly and land silently.
#
# Both sides of the comparison are hashed HERE, in Python, and the browser only
# stores and echoes back the opaque map it was given. Hashing client-side would
# mean reproducing Python's canonical JSON in JS, and any disagreement would make
# every item look changed on both sides — i.e. permanent false conflicts.


def _idea_fingerprint(idea: dict) -> str:
    """Stable hash of one idea's meaningful content.

    Empty values are pruned first so "absent" and "present but empty" hash the
    same — the serializer omits both, so they are not a real difference and must
    not read as an edit.
    """
    pruned = {k: v for k, v in idea.items()
              if not (v is None or v == "" or v == [] or v is False)}
    canon = json.dumps(pruned, sort_keys=True, separators=(",", ":"),
                       ensure_ascii=False, default=str)
    return hashlib.sha1(canon.encode("utf-8")).hexdigest()[:16]


def block_fingerprint(value) -> str:
    """Fingerprint of a whole groups/players/epics block, for the same purpose."""
    canon = json.dumps(value or [], sort_keys=True, separators=(",", ":"),
                       ensure_ascii=False, default=str)
    return hashlib.sha1(canon.encode("utf-8")).hexdigest()[:16]


def vocab_fingerprints(data: dict) -> dict:
    """Baseline hashes for the vocab blocks, in the shape the CLIENT holds them.

    Must hash vocab()'s projection, not the raw file blocks: the browser is given
    (and posts back) `{id,title,order}` groups, a merged player roster and
    trimmed epics. Hashing the raw block instead would never match, so every
    save would look like a vocab edit and quietly overwrite an external one.
    """
    v = vocab(data)
    return {k: block_fingerprint(v.get(k) or [])
            for k in ("groups", "players", "epics")}


def fingerprints(ideas) -> dict:
    """{id: fingerprint} for a list of ideas. Ideas with no id are skipped."""
    return {i["id"]: _idea_fingerprint(i) for i in (ideas or []) if i.get("id")}


def changed_ids(base: dict, now) -> set:
    """Ids that differ between a fingerprint baseline and a list of ideas.

    Covers edits (fingerprint moved), additions (id absent from the baseline)
    and deletions (id in the baseline but gone now).
    """
    fps = fingerprints(now)
    return ({i for i, fp in fps.items() if base.get(i) != fp}
            | {i for i in base if i not in fps})


def merge_ideas(base: dict, client_ideas, disk_ideas):
    """Three-way merge of the client's ideas onto what is now on disk.

    Returns (merged_ideas, overlapping_ids). A non-empty overlap means both
    sides edited the same idea and the caller must refuse the write; the merge
    result is meaningless in that case.
    """
    mine = changed_ids(base, client_ideas)
    theirs = changed_ids(base, disk_ideas)
    overlap = sorted(mine & theirs)
    if overlap:
        return None, overlap
    client_by_id = {i["id"]: i for i in client_ideas if i.get("id")}
    deleted = {i for i in mine if i not in client_by_id}
    merged, seen = [], set()
    # Disk order wins for everything that survives, so an external reordering or
    # insertion is preserved rather than being undone by our stale copy.
    for idea in disk_ideas:
        iid = idea.get("id")
        if iid in deleted:
            continue
        if iid in mine:                 # our edit to an item they left alone
            merged.append(client_by_id[iid])
        else:                           # theirs, or untouched by both
            merged.append(idea)
        seen.add(iid)
    # Anything we added (or that they deleted and we still edited) goes in at the
    # position it holds in our copy, so a new idea lands next to its neighbours.
    for pos, idea in enumerate(client_ideas):
        iid = idea.get("id")
        if iid in seen or iid in deleted:
            continue
        at = next((n for n, m in enumerate(merged)
                   if m.get("id") == (client_ideas[pos - 1].get("id")
                                      if pos else None)), None)
        merged.insert(at + 1 if at is not None else len(merged), idea)
        seen.add(iid)
    return merged, []


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
    epics = [{"id": e["id"], "title": e.get("title", ""), "group": e.get("group"),
              "status": e.get("status"), "notes": e.get("notes")}
             for e in (data.get("epics", []) or [])]
    return {"groups": groups, "players": players, "statuses": statuses,
            "types": types, "ids": ids, "epics": epics}


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
MERIT_RATE_UAT = 1       # one UAT / validation credit (not tied to idea type)


# The in-game "Recent Updates" sign DB (roadmapdb) is written by
# bin/roadmap_publish.py, which lives outside this file so the nightly wiki
# refresh can push the sign without starting a web server. Re-exported here
# because Publish to Wiki & DB calls it — and because nwn_home_dir() decides
# which SEASON's campaign DBs the editor touches, meritdb included.
SHIPPED_STATUSES = PUB.SHIPPED_STATUSES
# roadmap_auth.py keeps its own copy of this set so it stays importable without
# loading gen-roadmap.py (the CLI and the self-test have no use for it). The two
# drifting apart would silently widen or narrow what a DM may promote, so say so
# at startup rather than discover it from a permissions bug.
if set(SHIPPED_STATUSES) != set(AUTH.SHIPPED_STATUSES):
    print(f"[warn] SHIPPED_STATUSES disagree: roadmap_publish={sorted(SHIPPED_STATUSES)} "
          f"roadmap_auth={sorted(AUTH.SHIPPED_STATUSES)}", file=sys.stderr)
nwn_home_dir = PUB.nwn_home_dir
recent_db_path = PUB.recent_db_path
html_to_plain = PUB.html_to_plain
sync_recent_updates_db = PUB.sync_recent_updates_db


# The meritdb access layer and the roadmap-name -> meritdb bridge live in
# bin/roadmap_merit.py so bin/roadmap-users.py can use the SAME resolver when it
# binds an account to a player name. A binding this editor's award path cannot
# resolve is a tester who works for weeks and then cannot be paid, so there is
# one implementation of the rule, not two. Re-exported under the names this file
# already uses.
SHARED_DB_DIR = MERIT.SHARED_DB_DIR
merit_db_path = MERIT.merit_db_path
merit_db_problem = MERIT.merit_db_problem
_merit_text = MERIT.merit_text
_merit_connect = MERIT.merit_connect
_has_uat_column = MERIT.has_uat_column
_row_uat = MERIT.row_uat
_name_candidates = MERIT.name_candidates
_resolve_player_row = MERIT.resolve_player_row


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
        uat = _row_uat(row)
        spent = row["merit_spent"] or 0
        earned = (bugs * MERIT_RATE_BUG + features * MERIT_RATE_FEATURE
                  + exploits * MERIT_RATE_EXPLOIT + uat * MERIT_RATE_UAT)
        txns = [dict(r) for r in con.execute(
            "SELECT reward_label, reward_id, item_tag, cost, status, "
            "requested_at, resolved_at, needs_dm FROM redemptions "
            "WHERE cdkey = ? ORDER BY id DESC",
            (row["cdkey"],)).fetchall()]
        return {
            "available": True, "matched": True,
            "matched_name": row["name"], "last_login": row["last_login"],
            "bugs": bugs, "exploits": exploits, "features": features,
            "uat": uat,
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
# In-game merit database (write) — the Award / Revoke buttons
# --------------------------------------------------------------------------
# In-game, a DM's EmoteWand awards merit by bumping ONE counter column and
# writing one merit_ledger row (merit_award_bug/exp/ftr.nss). The editor's
# "Award merit" button does exactly the same thing, so the two paths stay
# indistinguishable in the ledger apart from the "(roadmap:<id>)" suffix.
#
# Which column an idea pays into is decided solely by its `type`.
MERIT_COLUMN = {"Defect": "bugs", "Enhancement": "features",
                "Exploit": "exploits"}
MERIT_POINTS = {"Defect": MERIT_RATE_BUG, "Enhancement": MERIT_RATE_FEATURE,
                "Exploit": MERIT_RATE_EXPLOIT}
# Ledger wording, matching the in-game award scripts verbatim.
MERIT_REASON = {"Defect": "defect report",
                "Enhancement": "feature implementation",
                "Exploit": "exploit report"}
# A UAT credit pays whoever helped VALIDATE the fix. It is independent of the
# idea's type (and of who reported it), so it has its own column, its own flat
# rate, and its own ledger wording — matching merit_award_uat.nss in game.
UAT_COLUMN = "uat"
UAT_REASON = "UAT validation"
# Roadmap player name -> meritdb cdkey, for names the fuzzy matcher can't reach
# ("Piskan (Alec Cain)" vs the DB's "Alek Cain"). Written when you pick a player
# by hand in the award dialog, so the same name resolves silently next time.
MERIT_ALIAS_PATH = MERIT.MERIT_ALIAS_PATH
read_merit_aliases = MERIT.read_merit_aliases
write_merit_alias = MERIT.write_merit_alias


def merit_players() -> dict:
    """Every meritdb player, most recently seen first — the award-dialog picker."""
    con = _merit_connect()
    if con is None:
        return {"available": False, "rows": [],
                "reason": f"meritdb not found at {merit_db_path()}"}
    try:
        uat_col = ", uat" if _has_uat_column(con) else ""
        rows = [dict(r) for r in con.execute(
            "SELECT cdkey, name, last_login, bugs, exploits, features, "
            f"merit_spent{uat_col} FROM players ORDER BY last_login DESC").fetchall()]
        for r in rows:
            r.setdefault("uat", 0)
            r["earned"] = ((r["bugs"] or 0) * MERIT_RATE_BUG
                           + (r["features"] or 0) * MERIT_RATE_FEATURE
                           + (r["exploits"] or 0) * MERIT_RATE_EXPLOIT
                           + (r["uat"] or 0) * MERIT_RATE_UAT)
            r["balance"] = r["earned"] - (r["merit_spent"] or 0)
        return {"available": True, "rows": rows}
    finally:
        con.close()


def _earned(row) -> int:
    return ((row["bugs"] or 0) * MERIT_RATE_BUG
            + (row["features"] or 0) * MERIT_RATE_FEATURE
            + (row["exploits"] or 0) * MERIT_RATE_EXPLOIT
            + _row_uat(row) * MERIT_RATE_UAT)


def award_merit(roadmap_name: str, idea_type: str, idea_id: str,
                cdkey: str = "", revoke: bool = False,
                kind: str = "submit") -> dict:
    """Credit (or take back) one idea's merit in the live meritdb.

    One BEGIN IMMEDIATE transaction: resolve the player row, move the counter,
    re-read it to prove the move landed, then write the ledger row. Anything
    that doesn't check out rolls the whole thing back and returns ok=False, so
    the caller can leave the roadmap status alone.

    Never INSERTs a players row: in-game rows are created on login only
    (Merit_RecordLogin), and inventing one here would mint merit for a cdkey
    that may not exist. An unmatched name is an error, not a new player.
    """
    if kind == "uat":
        col, points, reason = UAT_COLUMN, MERIT_RATE_UAT, UAT_REASON
    else:
        col = MERIT_COLUMN.get(idea_type)
        if not col:
            return {"ok": False,
                    "reason": f"idea type {idea_type or '(none)'} carries no merit value"}
        points, reason = MERIT_POINTS[idea_type], MERIT_REASON[idea_type]
    db = merit_db_path()
    if not db.exists():
        return {"ok": False, "reason": f"meritdb not found at {db}"}
    step = -1 if revoke else 1
    verb = "revoke" if revoke else "award"
    try:
        # The live server holds this file open, hence the busy timeout.
        con = sqlite3.connect(str(db), timeout=10.0)
    except sqlite3.Error as e:
        return {"ok": False, "reason": f"cannot open meritdb: {e}"}
    con.text_factory = _merit_text
    con.row_factory = sqlite3.Row
    con.isolation_level = None      # we drive the transaction by hand
    try:
        con.execute("BEGIN IMMEDIATE")
        if kind == "uat" and not _has_uat_column(con):
            return {"ok": False,
                    "reason": "meritdb has no `uat` column yet — it is added by "
                              "Merit_InitDb() at module load, so repack and let "
                              "the server reboot before awarding UAT merit"}
        row = None
        if cdkey:
            row = con.execute("SELECT * FROM players WHERE cdkey = ?",
                              (cdkey,)).fetchone()
            if row is None:
                return {"ok": False, "matched": False,
                        "reason": f"no meritdb player with cdkey {cdkey}"}
        else:
            alias = read_merit_aliases().get(roadmap_name)
            if alias:
                row = con.execute("SELECT * FROM players WHERE cdkey = ?",
                                  (alias,)).fetchone()
            if row is None:
                row = _resolve_player_row(con, roadmap_name)
        if row is None:
            return {"ok": False, "matched": False,
                    "reason": f"no meritdb player matched "
                              f"'{roadmap_name or '(no submitter)'}'"}
        key, name = row["cdkey"], row["name"]
        before = row[col] or 0
        if revoke and before <= 0:
            return {"ok": False,
                    "reason": f"{name} has no {col} left to take back"}
        cur = con.execute(f"UPDATE players SET {col} = {col} + ? WHERE cdkey = ?",
                          (step, key))
        if cur.rowcount != 1:
            return {"ok": False,
                    "reason": f"merit update touched {cur.rowcount} rows, expected 1"}
        after = con.execute("SELECT * FROM players WHERE cdkey = ?",
                            (key,)).fetchone()
        # Prove the counter really moved before we claim it did.
        if after is None or (after[col] or 0) != before + step:
            return {"ok": False,
                    "reason": f"merit counter did not move ({col}: {before} -> "
                              f"{after[col] if after else 'gone'})"}
        balance = _earned(after) - (after["merit_spent"] or 0)
        con.execute(
            "INSERT INTO merit_ledger (cdkey, player_name, delta, balance_after, "
            "reason, redemption_id) VALUES (?, ?, ?, ?, ?, 0)",
            (key, name, step * points, balance,
             f"{verb}: {reason} (roadmap:{idea_id})"))
        con.execute("COMMIT")
        return {"ok": True, "matched": True, "cdkey": key, "matched_name": name,
                "points": points, "delta": step * points, "column": col,
                "balance": balance,
                "message": (f"{'Revoked' if revoke else 'Awarded'} {points} merit "
                            f"{'from' if revoke else 'to'} {name} "
                            f"({idea_type}); balance now {balance}.")}
    except sqlite3.Error as e:
        return {"ok": False, "reason": f"meritdb error: {e}"}
    finally:
        # Any early return above left the transaction open — undo it.
        try:
            if con.in_transaction:
                con.execute("ROLLBACK")
        except sqlite3.Error:
            pass
        con.close()


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


# Text that YAML would read back as something other than a string. A git hash
# that happens to be all digits ("45167215955") round-trips as an int, and the
# whole toolchain then treats a number as a commit ref — the editor threw
# mid-render on exactly that. Quote these so a string stays a string.
_NUMERICISH_RE = re.compile(r"[-+]?(\d[\d_]*)(\.\d*)?([eE][-+]?\d+)?$")
_YAML_WORDS = {"true", "false", "yes", "no", "on", "off", "null", "~"}


def looks_non_string(s: str) -> bool:
    return bool(_NUMERICISH_RE.match(s)) or s.lower() in _YAML_WORDS


def emit_scalar(field: str, value) -> str:
    if isinstance(value, bool):
        return "true" if value else "false"
    s = str(value)
    if field in QUOTED_FIELDS:
        return dquote(s)
    # Only for fields that are conceptually text. The genuinely numeric fields
    # (the *_h heights) must stay bare or they fail validation on reload.
    if field not in HEIGHT_KEYS and looks_non_string(s):
        return dquote(s)
    if field == "player" and not re.fullmatch(r"[A-Za-z0-9_]+", s):
        return dquote(s)
    return s


def _emit_heights(item: dict, keys) -> list[str]:
    """Emit the persisted textarea heights present on a hand-off sub-item."""
    out = []
    for key in keys:
        val = item.get(key)
        if isinstance(val, int) and val > 0:
            out.append(f"        {key}: {val}")
    return out


def normalize_step(item) -> dict:
    """Coerce one manual_steps entry to the canonical mapping form.

    The field was originally a plain list of strings. Those still parse, and
    upgrade to {step, status: open} on the next save — so old YAML written by
    hand (or by an older autopilot run) keeps working with no migration pass.
    """
    if not isinstance(item, dict):
        return {"step": str(item), "status": "open", "blocker": False,
                "kind": GEN.DEFAULT_STEP_KIND}
    kind = item.get("kind")
    out = {
        "step": str(item.get("step", "")),
        "status": item.get("status", "open"),
        "kind": kind if kind in GEN.STEP_KINDS else GEN.DEFAULT_STEP_KIND,
        "blocker": bool(item.get("blocker", False)),
    }
    # `tester` says what it TAKES to run the check ("a wizard past 40");
    # `claimed_by` / `tested_by` say who actually did, and are stamped by the
    # server from the caller's bound player name -- never taken from a form.
    for key in ("tester", "claimed_by", "result", "tested_by", "tested_on"):
        val = item.get(key)
        if isinstance(val, str) and val.strip():
            out[key] = val.strip()
    if isinstance(item.get("step_h"), int):
        out["step_h"] = item["step_h"]
    return out


def normalize_steps(val) -> list:
    return [normalize_step(s) for s in val] if isinstance(val, list) else val


def normalize_uat_credit(item) -> dict:
    """One uat_credits entry in stored form. A bare string is the shorthand."""
    if isinstance(item, str):
        item = {"player": item}
    return {"player": str(item.get("player", "")).strip(),
            "awarded": bool(item.get("awarded", False)),
            "date": str(item.get("date") or "").strip()}


def normalize_uat_credits(val) -> list:
    return ([normalize_uat_credit(c) for c in val]
            if isinstance(val, list) else val)


def normalize_comment(item) -> dict:
    """One `comments` entry in stored form. A bare string is the shorthand.

    `author` and `date` are stamped by the server when the comment is appended
    (see _comment_write); nothing in the browser can choose them.
    """
    if isinstance(item, str):
        item = {"text": item}
    return {"author": str(item.get("author", "")).strip(),
            "date": str(item.get("date") or "").strip(),
            "text": str(item.get("text", "")).strip()}


def normalize_comments(val) -> list:
    return [normalize_comment(c) for c in val] if isinstance(val, list) else val


def emit_list_field(field: str, val: list) -> list[str]:
    """Emit an internal list field as a YAML block sequence under `field:`.

    manual_steps is a list of {step, status, kind, blocker} mappings (plus
    `tester` on UAT steps); design_questions a list of {question, status,
    answer}; uat_credits a list of {player, awarded, date}. They carry optional
    `*_h` textarea heights. All are internal (never rendered on the public
    board) — see CLAUDE-roadmap.md.
    """
    lines = [f"    {field}:"]
    for item in val:
        if field == UAT_FIELD:
            item = normalize_uat_credit(item)
            lines.append(f'      - player: {dquote(item["player"])}')
            if item["awarded"]:
                lines.append("        awarded: true")
            if item.get("date"):
                lines.append(f'        date: {dquote(item["date"])}')
            continue
        if field == "manual_steps":
            item = normalize_step(item)
            lines.append(f'      - step: {dquote(item["step"])}')
            lines.append(f'        status: {item["status"]}')
            lines.append(f'        kind: {item["kind"]}')
            if item.get("tester"):
                lines.append(f'        tester: {dquote(item["tester"])}')
            if item["blocker"]:
                lines.append("        blocker: true")
            # The tester's half of the step. Each is emitted only when set, so
            # a step nobody has touched serializes exactly as it did before
            # these fields existed (the no-op-save invariant).
            for key in ("claimed_by", "result", "tested_by", "tested_on"):
                if item.get(key):
                    lines.append(f'        {key}: {dquote(item[key])}')
            lines.extend(_emit_heights(item, ("step_h",)))
            continue
        if field == COMMENTS_FIELD:
            item = normalize_comment(item)
            lines.append(f'      - author: {dquote(item["author"])}')
            lines.append(f'        date: {dquote(item["date"])}')
            lines.append(f'        text: {dquote(item["text"])}')
            continue
        lines.append(f'      - question: {dquote(str(item.get("question", "")))}')
        lines.append(f'        status: {item.get("status", "open")}')
        answer = item.get("answer")
        lines.append("        answer: null" if answer in (None, "")
                     else f"        answer: {dquote(str(answer))}")
        lines.extend(_emit_heights(item, ("question_h", "answer_h")))
    return lines


def emit_unknown(field: str, value) -> list[str]:
    """Emit a field the editor doesn't model, as faithfully as we can.

    The idea body is regenerated from the edited data rather than preserved
    verbatim, so a key outside FIELD_ORDER used to be dropped in silence — that
    is how three ideas' `fix:` text would have been lost on the next GUI save.
    Nothing renders these (gen-roadmap.py warns about them), but a save must
    never delete data it merely failed to recognise.
    """
    if isinstance(value, (list, dict)):
        dumped = yaml.safe_dump(value, default_flow_style=True, width=10 ** 6,
                                allow_unicode=True, sort_keys=False).strip()
        return [f"    {field}: {dumped}"]
    if value is None:
        return [f"    {field}: null"]
    if isinstance(value, bool):
        return [f"    {field}: {'true' if value else 'false'}"]
    if isinstance(value, (int, float)):
        return [f"    {field}: {value}"]
    return [f"    {field}: {dquote(str(value))}"]


def serialize_ideas(ideas: list[dict], prefixes: dict, trailing: list[str]) -> str:
    out: list[str] = []
    for idea in ideas:
        iid = idea.get("id", "")
        for pre in prefixes.get(iid, []):
            out.append(pre)
        first = True
        for field in FIELD_ORDER:
            val = idea.get(field)
            if val is None or val == "" or val == [] or val is False:
                continue
            if field in LIST_FIELDS:
                # id is always emitted first, so a list field is never the
                # `- ` line; assert that rather than silently mis-indenting.
                if first:
                    raise ValueError(f"'{iid}': {field} cannot be the first field")
                out.extend(emit_list_field(field, val))
                continue
            scalar = emit_scalar(field, val)
            if first:
                out.append(f"  - {field}: {scalar}")
                first = False
            else:
                out.append(f"    {field}: {scalar}")
        # Carry through anything the editor doesn't model, in its original order,
        # after the known fields.
        for field in idea:
            if field not in FIELD_ORDER:
                out.extend(emit_unknown(field, idea[field]))
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


def serialize_epics(epics: list[dict]) -> str:
    """Emit the `epics:` block — umbrella items that ideas hang off via `epic:`."""
    out: list[str] = []
    for e in epics:
        out.append(f"  - id: {e['id']}")
        out.append(f'    title: {dquote(str(e.get("title", "")))}')
        out.append(f"    group: {e.get('group', '')}")
        if str(e.get("status") or "").strip():
            out.append(f"    status: {e['status']}")
        if str(e.get("notes") or "").strip():
            out.append(f'    notes: {dquote(str(e["notes"]))}')
    return "\n".join(out)


def ensure_block(text: str, key: str, before: str) -> str:
    """Guarantee a top-level `key:` exists, inserting an empty one if it doesn't.

    replace_block() assumes the key is already in the file; `epics:` is new, so a
    roadmap.yaml written before this feature has no such line. Insert it just
    above `before:` (with a blank line) so the file keeps its section rhythm.
    """
    if re.search(rf"^{re.escape(key)}:\s*$", text, re.M):
        return text
    lines = text.splitlines()
    idx = next(i for i, ln in enumerate(lines)
               if re.match(rf"^{re.escape(before)}:\s*$", ln))
    # Attach above any comment block that introduces `before:`.
    while idx > 0 and (lines[idx - 1].strip() == ""
                       or lines[idx - 1].lstrip().startswith("#")):
        idx -= 1
    lines[idx:idx] = [f"{key}:", ""]
    return "\n".join(lines) + ("\n" if text.endswith("\n") else "")


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


# Serializes every writer of roadmap.yaml: this server's request threads and
# bin/roadmap-apply-patch.py alike. Without it there is a multi-second window
# between the read that a merge is computed from and the os.replace() that
# commits it, and an external write landing inside that window is lost with no
# error anywhere.
LOCK_PATH = REPO / ".roadmap.yaml.lock"


@contextlib.contextmanager
def yaml_lock(timeout: float = 15.0):
    """Exclusive advisory lock on roadmap.yaml, held across read→merge→write."""
    deadline = time.monotonic() + timeout
    fh = open(LOCK_PATH, "a+")
    try:
        while True:
            try:
                fcntl.flock(fh, fcntl.LOCK_EX | fcntl.LOCK_NB)
                break
            except BlockingIOError:
                if time.monotonic() >= deadline:
                    raise TimeoutError(
                        f"another process has held {LOCK_PATH.name} for "
                        f"{timeout:g}s")
                time.sleep(0.05)
        yield
    finally:
        try:
            fcntl.flock(fh, fcntl.LOCK_UN)
        finally:
            fh.close()


# The audit entry the current request is writing under, so write_document()
# can hang a per-field diff off it without every handler having to thread an id
# through. Thread-local because ThreadingHTTPServer gives each request its own
# thread; armed by Handler._audit_write() and cleared at the top of do_POST, so
# a reused thread can never attribute a diff to the previous request. Unarmed
# outside the server (roadmap-apply-patch.py, roadmap-lint.py), where the whole
# hook is a no-op.
_audit_ctx = threading.local()


def arm_audit_diff(audit_id: int | None, ts: int | None = None) -> None:
    _audit_ctx.audit_id = audit_id or 0
    _audit_ctx.ts = int(ts if ts is not None else time.time())


def _record_audit_diff(before_ideas, after_ideas) -> None:
    """Store the field-level diff of the write that just landed. Never raises."""
    audit_id = getattr(_audit_ctx, "audit_id", 0)
    if not audit_id:
        return
    try:
        rows = idea_field_diff(before_ideas, after_ideas)
        if rows:
            AUTH.audit_diff(auth_db(), audit_id,
                            getattr(_audit_ctx, "ts", None) or int(time.time()), rows)
    except Exception:
        # Same contract as AUTH.audit(): a lost diff is bad, failing the write
        # it was describing is worse. The write has already landed by now.
        pass


def write_document(ideas: list[dict], groups: list[dict] | None = None,
                   players: list[str] | None = None,
                   epics: list[dict] | None = None) -> None:
    """Rewrite the ideas block, plus groups/players/epics when supplied; everything
    else (meta/redemption/housing and all comments) is preserved verbatim."""
    # Pre-image for the audit diff, taken under the caller's yaml_lock. Only
    # read when a request armed the context: one extra parse on an audited
    # write (a save already does several), none at all from the CLI.
    pre_ideas = (read_yaml().get("ideas") or []
                 if getattr(_audit_ctx, "audit_id", 0) else None)
    text = YAML_PATH.read_text(encoding="utf-8")
    if groups is not None:
        text = replace_block(text, "groups", serialize_groups(groups))
    if players is not None:
        text = replace_block(text, "players", serialize_players(players))
    if epics is not None:
        # Only materialize the block once there is something to put in it, so an
        # unchanged save on a file that predates epics stays a byte-for-byte no-op.
        if epics or re.search(r"^epics:\s*$", text, re.M):
            text = ensure_block(text, "epics", before="ideas")
            text = replace_block(text, "epics", serialize_epics(epics))
    new_text = replace_ideas_block(text, ideas)
    # Same directory as the target: os.replace() is only atomic within a
    # filesystem, and a tmp dir elsewhere fails outright across devices.
    fd, tmp = tempfile.mkstemp(dir=str(YAML_PATH.parent), prefix=".roadmap.",
                               suffix=".tmp")
    try:
        with os.fdopen(fd, "w", encoding="utf-8") as f:
            f.write(new_text)
        os.replace(tmp, YAML_PATH)
    except BaseException:
        if os.path.exists(tmp):
            os.unlink(tmp)
        raise
    if pre_ideas is not None:
        _record_audit_diff(pre_ideas, ideas)


def validate_internal_fields(ideas) -> list[str]:
    """Shape checks for the admin-only design_questions / manual_steps fields."""
    errs: list[str] = []
    for idea in ideas or []:
        iid = idea.get("id", "?")
        steps = idea.get("manual_steps")
        if steps is not None:
            if not isinstance(steps, list):
                errs.append(f"'{iid}': manual_steps must be a list")
            else:
                for s in steps:
                    # A bare string is the legacy form — valid, upgraded on save.
                    if isinstance(s, str):
                        if not s.strip():
                            errs.append(f"'{iid}': manual_steps entries must be "
                                        f"non-empty")
                        continue
                    if not isinstance(s, dict) or not str(s.get("step", "")).strip():
                        errs.append(f"'{iid}': each manual_step needs a 'step'")
                    elif s.get("status") not in STEP_STATUS:
                        errs.append(f"'{iid}': manual_step status must be "
                                    f"{'|'.join(STEP_STATUS)}, got "
                                    f"{s.get('status')!r}")
                    elif not isinstance(s.get("blocker", False), bool):
                        errs.append(f"'{iid}': manual_step blocker must be "
                                    f"true/false")
                    elif s.get("kind") is not None \
                            and s["kind"] not in GEN.STEP_KINDS:
                        errs.append(f"'{iid}': manual_step kind must be "
                                    f"{'|'.join(GEN.STEP_KINDS)}, got "
                                    f"{s['kind']!r}")
                    elif s.get("tester") is not None \
                            and not isinstance(s["tester"], str):
                        errs.append(f"'{iid}': manual_step tester must be text")
                    else:
                        for key in ("claimed_by", "result", "tested_by"):
                            if s.get(key) is not None and not isinstance(s[key], str):
                                errs.append(f"'{iid}': manual_step {key} must "
                                            f"be text")
                        on = str(s.get("tested_on") or "").strip()
                        if on and not re.fullmatch(r"\d{4}-\d{2}-\d{2}", on):
                            errs.append(f"'{iid}': manual_step tested_on must "
                                        f"be YYYY-MM-DD, got {on!r}")
        credits = idea.get(UAT_FIELD)
        if credits is not None:
            if not isinstance(credits, list):
                errs.append(f"'{iid}': {UAT_FIELD} must be a list")
            else:
                seen_players = set()
                for c in credits:
                    if isinstance(c, str):      # bare-name shorthand
                        c = {"player": c}
                    if not isinstance(c, dict) or not str(c.get("player", "")).strip():
                        errs.append(f"'{iid}': each {UAT_FIELD} entry needs a "
                                    f"'player'")
                        continue
                    if not isinstance(c.get("awarded", False), bool):
                        errs.append(f"'{iid}': {UAT_FIELD} awarded must be "
                                    f"true/false, got {c.get('awarded')!r}")
                    date = str(c.get("date") or "").strip()
                    if date and not re.fullmatch(r"\d{4}-\d{2}-\d{2}", date):
                        errs.append(f"'{iid}': {UAT_FIELD} date must be "
                                    f"YYYY-MM-DD, got {date!r}")
                    # One credit per player per idea — merit is paid per entry,
                    # so a duplicate name is a double payment waiting to happen.
                    name = str(c["player"]).strip().lower()
                    if name in seen_players:
                        errs.append(f"'{iid}': {UAT_FIELD} lists "
                                    f"'{c['player']}' more than once")
                    seen_players.add(name)
        comments = idea.get(COMMENTS_FIELD)
        if comments is not None:
            if not isinstance(comments, list):
                errs.append(f"'{iid}': {COMMENTS_FIELD} must be a list")
            else:
                for c in comments:
                    if isinstance(c, str):      # bare-text shorthand
                        c = {"text": c}
                    if not isinstance(c, dict) or not str(c.get("text", "")).strip():
                        errs.append(f"'{iid}': each {COMMENTS_FIELD} entry "
                                    f"needs a 'text'")
                        continue
                    if not str(c.get("author", "")).strip():
                        errs.append(f"'{iid}': each {COMMENTS_FIELD} entry "
                                    f"needs an 'author'")
                    date = str(c.get("date") or "").strip()
                    if date and not re.fullmatch(r"\d{4}-\d{2}-\d{2}", date):
                        errs.append(f"'{iid}': {COMMENTS_FIELD} date must be "
                                    f"YYYY-MM-DD, got {date!r}")
        if not isinstance(idea.get(MERIT_FLAG, False), bool):
            errs.append(f"'{iid}': {MERIT_FLAG} must be true/false, got "
                        f"{idea.get(MERIT_FLAG)!r}")
        qs = idea.get("design_questions")
        if qs is not None:
            if not isinstance(qs, list):
                errs.append(f"'{iid}': design_questions must be a list")
            else:
                for q in qs:
                    if not isinstance(q, dict) or not str(q.get("question", "")).strip():
                        errs.append(f"'{iid}': each design_question needs a 'question'")
                    elif q.get("status") not in ("open", "answered"):
                        errs.append(f"'{iid}': design_question status must be "
                                    f"open|answered, got {q.get('status')!r}")
        # A design-blocked item must say what it's blocked on, or nothing can
        # ever unblock it — the autopilot resume gate reads these.
        if idea.get("status") == "design":
            if not any(isinstance(q, dict) and q.get("status") == "open"
                       for q in (qs or [])):
                errs.append(f"'{iid}': status 'design' needs at least one "
                            f"design_question with status 'open'")
        # An item can't be on the shipped board while a blocking manual step is
        # still outstanding — that's exactly what status 'manual' is for.
        if idea.get("status") in ("implemented", "awarded"):
            n = len(open_blockers(idea))
            if n:
                errs.append(f"'{iid}': status '{idea['status']}' with {n} "
                            f"unfinished blocker manual_step(s) — finish them "
                            f"or set status 'manual'")
        # An unknown field is round-tripped by emit_unknown(); refuse to write one
        # whose value that emitter can't reproduce faithfully, rather than mangle it.
        for key, val in idea.items():
            if key in FIELD_ORDER:
                continue
            if not isinstance(val, (str, int, float, bool, list, dict, type(None))):
                errs.append(f"'{iid}': unrecognised field '{key}' holds a value "
                            f"this editor cannot round-trip ({type(val).__name__})")
        errs.extend(_height_errors(iid, idea))
    return errs


def _height_errors(iid: str, idea: dict) -> list[str]:
    """Persisted textarea heights must be positive ints wherever they appear."""
    errs = []
    items = [idea] + list(idea.get("design_questions") or []) \
                   + [s for s in (idea.get("manual_steps") or [])
                      if isinstance(s, dict)]
    for item in items:
        if not isinstance(item, dict):
            continue
        for key in HEIGHT_KEYS:
            val = item.get(key)
            if val is not None and (not isinstance(val, int)
                                    or isinstance(val, bool) or val <= 0):
                errs.append(f"'{iid}': {key} must be a positive integer, "
                            f"got {val!r}")
    return errs


def open_blockers(idea: dict) -> list[dict]:
    """Manual steps flagged as blockers that aren't done yet.

    Shared by the save-time gate, the editor's hand-off badge, and the autopilot
    resume rule — see CLAUDE-autopilot.md. Legacy bare-string steps are never
    blockers (the flag didn't exist when they were written).
    """
    return [s for s in (idea.get("manual_steps") or [])
            if isinstance(s, dict) and s.get("blocker")
            and s.get("status") != "done"]


def extra_validate(groups, players, epics=None) -> list[str]:
    """Structural checks for the editor-managed groups/players/epics blocks."""
    errs: list[str] = []
    if epics is not None:
        seen = set()
        gids = {g.get("id") for g in (groups or [])}
        for e in epics:
            eid = e.get("id", "")
            if not re.fullmatch(r"[a-z0-9-]+", eid or ""):
                errs.append(f"epic id '{eid}' must be lowercase letters/digits/hyphens")
            if eid in seen:
                errs.append(f"duplicate epic id '{eid}'")
            seen.add(eid)
            if not str(e.get("title", "")).strip():
                errs.append(f"epic '{eid}' needs a title")
            if groups is not None and e.get("group") not in gids:
                errs.append(f"epic '{eid}': unknown group {e.get('group')!r}")
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


def _err_class(msg: str) -> str:
    """A validation error with its counts masked — 'same complaint as before?'."""
    return re.sub(r"\d+", "#", msg)


def normalize_ideas(ideas, groups=None) -> None:
    """Coerce posted ideas (and group orders) in place into their stored form.

    Runs before both fingerprinting and validation: the three-way merge compares
    posted ideas against ideas read from disk, which are already in stored form,
    so normalizing only one side would make untouched items read as edited.
    """
    if groups is not None:
        for g in groups:
            if str(g.get("order", "")).strip() != "":
                try:
                    g["order"] = int(g["order"])
                except (TypeError, ValueError):
                    pass
    for it in ideas:
        # Heights arrive as JS numbers/strings; coerce to int, and drop the
        # key entirely rather than persisting junk that would fail validation.
        # Must run BEFORE normalize_steps, which keeps step_h only when it is
        # already an int and would otherwise discard the browser's float.
        for holder in ([it] + list(it.get("design_questions") or [])
                       + [s for s in (it.get("manual_steps") or [])
                          if isinstance(s, dict)]):
            for key in HEIGHT_KEYS:
                if key not in holder:
                    continue
                if str(holder.get(key, "")).strip() == "":
                    holder.pop(key, None)
                    continue
                try:
                    holder[key] = int(float(holder[key]))
                except (TypeError, ValueError):
                    holder.pop(key, None)
        if it.get("manual_steps"):
            it["manual_steps"] = normalize_steps(it["manual_steps"])
        if it.get(UAT_FIELD):
            it[UAT_FIELD] = normalize_uat_credits(it[UAT_FIELD])
        if it.get(COMMENTS_FIELD):
            it[COMMENTS_FIELD] = normalize_comments(it[COMMENTS_FIELD])
        if it.get("impl_notes"):
            it["impl_notes"] = sanitize_notes(it["impl_notes"])
        # Strip any pasted chrome (e.g. Discord DOM) down to the whitelist
        # so the YAML — and every regenerate/publish from it — stays clean.
        if it.get("notes"):
            it["notes"] = sanitize_notes(it["notes"])


def validate_document(ideas, groups=None, players=None,
                      epics=None) -> tuple[list[str], list[str]]:
    """Run gen-roadmap's validate() plus our structural checks."""
    data = read_yaml()
    data["ideas"] = ideas
    if groups is not None:
        data["groups"] = groups
    if players is not None:
        data["players"] = players
    if epics is not None:
        data["epics"] = epics
    buf = io.StringIO()
    with redirect_stderr(buf):
        errors = GEN.validate(data)
    errors = (list(errors) + extra_validate(groups, players, epics)
              + validate_internal_fields(ideas))
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
# Palette Finder — search where a blueprint lives in the toolset palette.
# Backed by module-index/palette_map.json (bin/gen-palette-map.py). Standalone:
# the Refresh button reruns that generator; it never touches the wiki or git.
# --------------------------------------------------------------------------
def load_palette_map() -> dict:
    """{'built': <iso or None>, 'entries': [...]} — empty if not built yet."""
    if not PALETTE_MAP_PATH.exists():
        return {"built": None, "entries": []}
    try:
        doc = json.loads(PALETTE_MAP_PATH.read_text(encoding="utf-8"))
    except (OSError, ValueError):
        return {"built": None, "entries": []}
    return {"built": doc.get("generated"), "entries": doc.get("entries", [])}


def search_palette(query: str, limit: int = 100) -> dict:
    data = load_palette_map()
    entries = data["entries"]
    q = (query or "").strip().lower()
    if q:
        hits = [e for e in entries
                if q in e.get("name", "").lower()
                or q in e.get("resref", "").lower()]
    else:
        hits = []
    return {"built": data["built"], "total": len(entries),
            "matched": len(hits), "results": hits[:limit]}


def refresh_palette_map() -> tuple[bool, str]:
    proc = subprocess.run(
        [sys.executable, str(PALETTE_GEN_PATH)],
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


# --------------------------------------------------------------------------
# Server log monitor — every realm on this box, interleaved
# --------------------------------------------------------------------------
# NO FALLBACK CONTAINER NAME, deliberately, anywhere below. This page used to
# tail a single container defaulting to the literal "nwnxee-homer-s2", which was
# harmless while that was the only container on the box and actively wrong the
# moment it was not: there are three environments (dev, the live season, an
# archived season), each with its own container, and a default silently tails
# SOMEONE ELSE'S SERVER. An admin reading the monitor page would be watching the
# wrong realm's log while believing it was this one — and log output looks
# plausible either way, so nothing about the screen would give it away. That is
# also why every line here carries its realm tag.
#
# Guessing is what caused the roadmapdb misrouting incident recorded in
# roadmap_publish.nwn_home_dir(). A loud failure is strictly better than a
# confident wrong answer.


# Colours match bin/watch-all-servers' ANSI palette (cyan / yellow / green).
_REALM_COLORS = {"DEV": "#56d4dd", "S1": "#d29922", "S2": "#3fb950"}
_EXTRA_COLORS = ["#d2a8ff", "#79c0ff", "#ff7b72"]


def env_get(text: str, key: str) -> str:
    """One assignment out of a server.env, last one wins.

    Shared by realms() and live_repo(); same parse as bin/promote-to-prod's
    read_var() and bin/roadmap_publish.py's nwn_home_dir(), so the three never
    disagree about which realm a repo is.
    """
    m = None
    for ln in text.splitlines():
        hit = re.match(rf"\s*(?:export\s+)?{key}\s*=\s*(.+?)\s*$", ln)
        if hit:
            m = hit
    if not m:
        return ""
    val = m.group(1).strip()
    # A quoted value ends at its closing quote, and server.env comments most of
    # its season block INLINE after the quote:
    #     SEASON_WIKI_URL="https://homerslotr.com/"   # apex for the live season
    # Taking the quoted span (rather than stripping quotes off the whole line)
    # is what keeps that comment out of the value.
    if val[:1] in ('"', "'"):
        end = val.find(val[0], 1)
        return val[1:end] if end != -1 else val[1:]
    return val.split("#", 1)[0].strip()


def live_repo() -> tuple["Path | None", str]:
    """The production repo to publish the roadmap page into: (path, message).

    THE TARGET IS DISCOVERED, NOT CONFIGURED — the same rule bin/promote-to-prod
    uses: sibling nwn_homers_lotr* checkouts whose server.env says
    SEASON_ROLE=live. (None, msg) when there is nothing to do or the answer is
    ambiguous:

      * this repo IS the live realm — the ordinary publish already did it;
      * no live sibling — a dev box with no production checked out beside it;
      * more than one live realm — during a cutover overlap "production" is
        genuinely ambiguous, and a button may not guess which site the public
        roadmap belongs on.
    """
    if env_get(SERVER_ENV.read_text(encoding="utf-8") if SERVER_ENV.exists() else "",
               "SEASON_ROLE") == "live":
        return None, "live realm publish: skipped — this repo IS the live realm."
    found = []
    for repo in sorted(REPO.parent.glob("nwn_homers_lotr*")):
        if repo == REPO:
            continue
        env_file = repo / "server.env"
        try:
            text = env_file.read_text(encoding="utf-8")
        except OSError:
            continue
        if env_get(text, "SEASON_ROLE") == "live":
            found.append(repo)
    if not found:
        return None, "live realm publish: skipped — no sibling repo has SEASON_ROLE=live."
    if len(found) > 1:
        names = ", ".join(r.name for r in found)
        return None, ("live realm publish: SKIPPED — several live realms "
                      f"({names}). Publish by hand during a cutover overlap.")
    return found[0], ""


def live_target_mismatch(target: Path) -> str:
    """Warn when the roadmap link and the publish target disagree about which
    site production is — "" when they agree or either side is unset.

    Two independent facts have to name the same wiki: SEASON_LIVE_WIKI_URL here
    (what the editor's one roadmap link points at, written by season-brand.py)
    and SEASON_WIKI_URL over in the realm we just published into. They are set
    by different steps of a season cutover, so they can drift for exactly as
    long as it takes someone to notice — and the failure is silent: the page
    lands on one host while the admin checks the other.
    """
    def env(repo: Path, key: str) -> str:
        f = repo / "server.env"
        try:
            return env_get(f.read_text(encoding="utf-8"), key)
        except OSError:
            return ""
    ours = env(REPO, "SEASON_LIVE_WIKI_URL")
    theirs = env(target, "SEASON_WIKI_URL")
    if not ours or not theirs or ours.rstrip("/") == theirs.rstrip("/"):
        return ""
    return (f" WARNING: this repo calls production {ours} but {target.name} "
            f"publishes to {theirs} — re-run bin/season-brand.py.")


def realms() -> list[dict]:
    """Every Homer's LotR realm on this box, newest season first.

    A realm is a sibling repo of this one (nwn_homers_lotr, _s1, _s2, ...) whose
    server.env sets NWN_CONTAINER_NAME. Same discovery rule, same no-guessing
    rule and the same tag rule (dev is keyed on ROLE, seasons on NUM) as
    bin/watch-all-servers and bin/season-shortcuts.sh — the three must agree or
    the terminal monitor and this page label the same log differently.

    Repos without a server.env (nwn_homers_lotr_2009) drop out on their own.
    """
    out, extra = [], 0
    for repo in sorted(REPO.parent.glob("nwn_homers_lotr*")):
        env_file = repo / "server.env"
        try:
            text = env_file.read_text(encoding="utf-8")
        except OSError:
            continue
        container = env_get(text, "NWN_CONTAINER_NAME")
        if not container:
            continue
        role = env_get(text, "SEASON_ROLE")
        num = env_get(text, "SEASON_NUM")
        if role == "dev":
            tag, label, color = "DEV", "TEST realm", _REALM_COLORS["DEV"]
        else:
            tag = f"S{num or '?'}"
            label = f"Season {num or '?'} ({role or '?'})"
            color = _REALM_COLORS.get(tag)
            if color is None:
                color = _EXTRA_COLORS[extra % len(_EXTRA_COLORS)]
                extra += 1
        out.append({"tag": tag, "label": label, "container": container,
                    "color": color, "repo": repo.name})
    # Live season above dev in the legend; dev is the noisiest and least urgent.
    out.sort(key=lambda r: (r["tag"] == "DEV", r["tag"]))
    return out


# podman --timestamps prefixes each line with RFC3339 nanoseconds, e.g.
# "2026-08-14T06:50:10.345643000-05:00 I [06:50:10] ...".
_TS_RE = re.compile(r"^(\d{4}-\d\d-\d\dT\d\d:\d\d:\d\d(?:\.\d+)?"
                    r"(?:Z|[+-]\d\d:?\d\d))\s?(.*)$", re.S)

# --- noise filter: the same blocklist bin/watch-all-servers uses --------------
# Roughly 95% of what the servers print is machinery talking to itself. The
# patterns live in bin/server-log-noise.txt so this page and the terminal
# monitor can never disagree about what a "clean" log looks like — see that
# file for the format and the rules on editing it.
NOISE_FILE = REPO / "bin" / "server-log-noise.txt"
_noise_cache: dict = {}

# Severity letters NWNX/Anvil actually emit: I=info N=notice W=warn E=error
# D=debug. W and E are exempt from the filter, always.
_SEV_RE = re.compile(r"^([IWEDN]) \[")
_FULL_TS_RE = re.compile(r"^\[\d{4}/\d\d/\d\d \d\d:\d\d:\d\d\.\d\d\d\] ")
_SHORT_TS_RE = re.compile(r"^\[\d\d:\d\d:\d\d\] ")
_LOGGER_RE = re.compile(r"^\[([A-Za-z][A-Za-z0-9_.]*)\] ")
_CPP_RE = re.compile(r"^\[[A-Za-z_]+\.cpp:\d+\] ")
# nwserver and NWNX share one fd, so records arrive welded together, e.g.
# `Server: Loading module "X"I [07:37:35] [NWNX_ServerLogRedirector] ...`.
_GLUE_RE = re.compile(r"(?<=.)(?=[IWEDN] \[\d)")


def noise_re() -> "re.Pattern | None":
    """Compiled blocklist, recompiled when the file changes on disk.

    Keyed on (mtime, size) rather than cached once: the editor is a long-lived
    systemd service, and an admin who edits the blocklist should not have to
    restart it to see the effect.
    """
    try:
        st = NOISE_FILE.stat()
        key = (st.st_mtime_ns, st.st_size)
    except OSError:
        return None
    if _noise_cache.get("key") != key:
        pats = [ln.strip() for ln in
                NOISE_FILE.read_text(encoding="utf-8").splitlines()]
        pats = [p for p in pats if p and not p.startswith("#")]
        _noise_cache.clear()
        _noise_cache["key"] = key
        _noise_cache["re"] = re.compile("|".join(pats)) if pats else None
    return _noise_cache.get("re")


def tidy_log_line(raw: str, keep_noise: bool = False) -> list[tuple[str, str]]:
    """One raw container line -> the (severity, message) rows worth showing.

    Drops boilerplate, splits welded records, and strips the parts this page
    already shows in its own columns: the severity letter, the engine's own
    timestamp (podman's stamp is more accurate and is the sort key), and the
    logger name. Message tags we emit ourselves — [FORGE], [Bestiary],
    [ServerRestart] — are deliberately kept: a logger is a dotted namespace or
    an NWNX_* plugin, nothing else.

    Returns [] when the whole line was noise.
    """
    noise = None if keep_noise else noise_re()
    out: list[tuple[str, str]] = []
    for rec in _GLUE_RE.split(raw):
        rec = rec.lstrip(".")          # module-load progress dots
        if not rec.strip():
            continue
        sev, body = "", rec
        if _SEV_RE.match(rec):
            sev, body = rec[0], rec[2:]
            for pat in (_FULL_TS_RE, _SHORT_TS_RE):
                m = pat.match(body)
                if m:
                    body = body[m.end():]
                    break
        msg = body
        m = _LOGGER_RE.match(msg)
        if m and ("." in m.group(1) or m.group(1).startswith("NWNX")):
            msg = msg[m.end():]
            msg = _CPP_RE.sub("", msg)
        if msg.startswith("(Server) "):
            msg = msg[len("(Server) "):]
        # Match with the logger attached AND stripped: some patterns key off the
        # logger, others anchor on the bare message.
        if (noise is not None and sev not in ("W", "E")
                and (noise.search(body) or noise.search(msg))):
            continue
        out.append((sev, msg))
    return out


def server_log_tail_all(tail: int = 400,
                        raw: bool = False) -> tuple[list[dict], list[dict]]:
    """Recent logs from EVERY realm, interleaved chronologically and filtered.

    The web equivalent of `bin/watch-all-servers`, and filtered by the same
    blocklist (see tidy_log_line) so the two monitors show the same log. `raw`
    turns the filter off, the page's "raw" checkbox.

    `--timestamps` is what makes a true interleave possible: the container
    streams share no other clock, so without it "combined" would just mean three
    blocks stacked. Lines with no stamp are continuations and inherit the
    previous line's time, which keeps a multi-line stack trace together.

    Because the blocklist drops ~95% of the stream, `tail` is raised before it
    is applied — otherwise "last 600 lines" would mean about 30 useful ones.

    Returns (realm status rows, log lines).
    """
    found = realms()
    if not found:
        return [], [{"tag": "", "time": "", "text": (
            "No realms found. A realm is a sibling repo of "
            f"{REPO.name} with NWN_CONTAINER_NAME set in its server.env. "
            "Refusing to guess a container name — a wrong guess silently shows "
            "another realm's server.")}]

    # Ask podman for far more than we intend to show, because the blocklist is
    # about to throw most of it away. Capped so a busy realm can't blow the
    # response up.
    fetch = tail if raw else min(6000, tail * 12)

    status, rows = [], []
    for r in found:
        up = subprocess.run(["podman", "container", "exists", r["container"]],
                            capture_output=True).returncode == 0
        status.append({**{k: r[k] for k in ("tag", "label", "container", "color")},
                       "ok": up})
        if not up:
            # \uffff sorts after every timestamp, so a down realm's notice sits
            # at the bottom of the stream where it is read last, rather than
            # buried somewhere in yesterday's log.
            rows.append(("\uffff" + r["tag"], r["tag"], "W",
                         f"container '{r['container']}' is not running — "
                         "waiting for it to come up..."))
            continue
        proc = subprocess.run(
            ["podman", "logs", "--timestamps", "--tail", str(fetch),
             r["container"]],
            capture_output=True, text=True,
        )
        text = (proc.stdout or "") + (proc.stderr or "")
        last = ""
        for line in text.rstrip("\n").splitlines():
            m = _TS_RE.match(line)
            if m:
                last, body = m.group(1), m.group(2)
            else:
                body = line
            # Sort key is the stamp; continuation lines reuse the previous one,
            # and a realm with no stamps at all sorts to the top rather than
            # crashing the merge. One raw line can yield several rows (welded
            # records) or none at all (noise).
            for sev, msg in tidy_log_line(body, keep_noise=raw):
                rows.append((last, r["tag"], sev, msg))

    # Lexicographic on the RFC3339 stamp is a correct chronological sort here
    # because every realm is a container on THIS host, so all stamps carry the
    # same UTC offset. (Cross-host realms would need real parsing.)
    rows.sort(key=lambda t: t[0])
    rows = rows[-tail:]                 # `tail` counts lines the admin SEES
    lines = [{"tag": tag, "time": (ts[11:19] if len(ts) >= 19 and ts[10:11] == "T"
                                   else ""), "sev": sev, "text": body}
             for ts, tag, sev, body in rows]
    if not lines:
        lines = [{"tag": "", "time": "", "sev": "",
                  "text": "(no log output yet)"}]
    return status, lines


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
#
# The same two steps run TWICE: once in this repo, and once in the live season's
# repo (see publish_to_live_realm below), because each realm's wiki is served
# from its OWN docs/ by its own Cloudflare worker and a git push is the deploy.
# --------------------------------------------------------------------------
def roadmap_body() -> str:
    """The <body> of the page gen-roadmap.py just wrote — what gets swapped into
    a published wiki page's outer <main>."""
    src = SRC_ROADMAP.read_text(encoding="utf-8")
    m = re.search(r"<body[^>]*>(.*?)</body>", src, re.IGNORECASE | re.DOTALL)
    return (m.group(1) if m else src).strip("\n")


def publish_roadmap_to_docs(repo: Path = REPO, body: str | None = None) -> tuple[bool, str]:
    """Replicate nwn-wiki's manual-page publish for the roadmap alone: take the
    freshly generated source body and swap it into the already-published page's
    outer <main>, preserving the wiki header/footer/nav from the last full build.

    `repo` may be another realm's checkout, in which case `body` is THIS repo's
    freshly rendered body: only the dev realm renders the page (see the realm
    guard in bin/gen-roadmap.py), so the target keeps its own header/nav and
    takes dev's content.
    """
    docs_roadmap = repo / "docs" / "manual" / "Roadmap.html"
    if not docs_roadmap.exists():
        return False, (f"{docs_roadmap} does not exist — run a "
                       "full `nwn-manager wiki` build once before publishing.")
    if body is None:
        body = roadmap_body()

    published = docs_roadmap.read_text(encoding="utf-8")
    # Greedy: <main> appears only in the body region, so this spans the first
    # <main> to the last </main> (the outer wiki <main>).
    swapped, n = re.subn(r"<main>.*</main>",
                         lambda _: f"<main>\n{body}\n  </main>",
                         published, count=1, flags=re.DOTALL)
    if not n:
        return False, f"could not find <main> block in {docs_roadmap}"
    docs_roadmap.write_text(swapped, encoding="utf-8")
    try:
        shown = docs_roadmap.relative_to(REPO.parent)
    except ValueError:
        shown = docs_roadmap
    return True, f"published {shown}"


def _git(*args: str, repo: Path = REPO) -> subprocess.CompletedProcess:
    return subprocess.run(["git", *args], cwd=str(repo),
                          capture_output=True, text=True)


# roadmap.yaml is deliberately absent from the live realm's pathspec: production
# gets the backlog file itself at the next bin/season-promote.sh, and that is
# what keeps its in-game Recent Updates sign showing PROMOTED work only.
LIVE_PUBLISH_PATHS = ["docs.manual/Roadmap.html", "docs/manual/Roadmap.html"]
DEV_PUBLISH_PATHS = ["roadmap.yaml", *LIVE_PUBLISH_PATHS]


def git_publish(repo: Path = REPO, paths: list[str] | None = None,
                rebase_first: bool = False) -> tuple[bool, str]:
    """Stage `paths`, commit with the standard message, and push. 'Nothing to
    commit' is treated as success (nothing to publish).

    `rebase_first` is for another realm's repo: its own wiki publisher commits
    and pushes to the same branch on a timer ("Auto Wiki Activity Refresh"), so
    a straight push can lose a race this repo never sees.
    """
    paths = paths or DEV_PUBLISH_PATHS
    label = "" if repo == REPO else f"[{repo.name}] "
    add = _git("add", "--", *paths, repo=repo)
    if add.returncode != 0:
        return False, f"{label}git add failed:\n{(add.stdout + add.stderr).strip()}"
    # Anything staged among our paths?
    staged = _git("diff", "--cached", "--quiet", "--", *paths, repo=repo)
    if staged.returncode == 0:
        return True, f"{label}nothing to commit — docs already up to date."
    commit = _git("commit", "-m", PUBLISH_COMMIT_MSG, "--", *paths, repo=repo)
    if commit.returncode != 0:
        return False, f"{label}git commit failed:\n{(commit.stdout + commit.stderr).strip()}"
    if rebase_first:
        # --autostash because the target realm is a WORKING repo, not a deploy
        # slot: its own wiki publisher leaves docs/ churn in the tree, and a
        # plain `pull --rebase` refuses outright on unstaged changes, which
        # would turn a routine race into a failed publish.
        _git("pull", "--rebase", "--autostash", "--quiet", repo=repo)
    push = _git("push", repo=repo)
    out = (commit.stdout + push.stdout + push.stderr).strip()
    if push.returncode != 0:
        return False, f"{label}committed but push failed:\n{out}"
    return True, f"{label}committed + pushed.\n{out}"


def publish_to_live_realm(body: str) -> tuple[bool, str]:
    """Copy the page this realm just rendered into the LIVE season's wiki, and
    push it — a git push to that repo IS the Cloudflare deploy.

    Why this exists: a player who reports a problem should see it tracked on the
    public roadmap right away, not at the next promotion. The PAGE travels now;
    roadmap.yaml and therefore the in-game Recent Updates sign still wait for
    bin/season-promote.sh, because those announce shipped code that production
    is not running yet.

    Both files are written: docs/manual/Roadmap.html is what the live site serves
    right now, and docs.manual/Roadmap.html is the source its next FULL wiki
    build folds back into docs/ — write only one and the nightly build undoes
    the publish.

    Never fatal. Everything here is a second realm on the same box, and no
    problem with it may cost this realm its own publish.
    """
    target, why = live_repo()
    if target is None:
        return True, why
    src = target / "docs.manual" / "Roadmap.html"
    if not src.parent.exists():
        return False, f"live realm publish FAILED: {src.parent} does not exist."
    ok, msg = publish_roadmap_to_docs(target, body)
    if not ok:
        return False, f"live realm publish FAILED: {msg}"
    src.write_text(SRC_ROADMAP.read_text(encoding="utf-8"), encoding="utf-8")

    # The credit sidecar travels with the page, for the same reason the page
    # travels: it is the other half of what a player sees. Without it the live
    # wiki renders player pages with no Ideas section at all, so a player who
    # reported a bug can read about it on the roadmap but is credited for it
    # nowhere -- and that credit is the whole point of the merit system.
    #
    # It is NOT committed (gitignored on both realms, derived from roadmap.yaml
    # on every gen-roadmap.py run). It only has to exist in the live realm's
    # working tree, because that is where that realm's own wiki build reads it.
    # Best-effort like everything else here: a missing or unwritable sidecar
    # must not cost this realm its publish.
    try:
        credits = GEN.CREDITS_PATH
        if credits.is_file():
            (target / credits.name).write_text(
                credits.read_text(encoding="utf-8"), encoding="utf-8")
    except OSError:
        pass

    git_ok, git_msg = git_publish(target, LIVE_PUBLISH_PATHS, rebase_first=True)
    return git_ok, (f"live realm ({target.name}): {msg}; {git_msg}"
                    + live_target_mismatch(target))


# --------------------------------------------------------------------------
# Access control
# --------------------------------------------------------------------------
# Which capability each route needs. Two entries are matched by prefix (noted
# below); everything else is an exact path match after the query string is
# stripped. A route missing from this table is DENIED, so adding an endpoint
# without deciding who may call it fails closed rather than shipping open.
#
# Ordering matters for the prefix entries in exactly the way the dispatch
# chains already document: "/api/meritplayers" must be tested before the
# "/api/merit" prefix or it is swallowed by it.
PUBLIC_ROUTES = frozenset(("/login", "/api/login"))
# Authenticated, but needing no particular capability.
ANY_USER_ROUTES = frozenset(("/api/logout", "/api/me"))

ROUTE_CAPS: dict[str, str] = {
    "/": "view",
    "/index.html": "view",
    "/api/data": "view",
    "/api/version": "view",
    # Read-only merit views: a DM may look, but /api/award is gated on `merit`.
    # `merit_view` rather than `view` so a `tester` -- who must see the whole
    # backlog -- does not also see every player's balance and redemptions.
    "/api/meritplayers": "merit_view",
    "/api/merit": "merit_view",
    "/api/pending": "merit_view",
    "/api/audit": "audit_view",
    "/monitor": "serverlog",
    "/api/serverlog": "serverlog",
    "/api/palette": "palette",
    "/api/palette/refresh": "palette",
    "/api/changes": "llm_review",
    "/api/changes/action": "llm_review",
    "/api/save": "edit",
    "/api/step-status": "edit",
    # The tester lane. Narrow single-step writes, which is why they are safe to
    # hand a role that has no `edit` at all.
    "/api/uat-claim": "uat",
    "/api/uat-result": "uat",
    "/api/idea-comment": "uat",
    "/api/regenerate": "publish",
    "/api/publish": "publish",
    "/api/award": "merit",
    "/api/revoke": "merit",
    "/api/uat-award": "merit",
    "/api/uat-revoke": "merit",
}
# Paths whose real route is a prefix of the request path (the dispatch chains
# use startswith for these). Longest first so /api/meritplayers wins.
PREFIX_ROUTES = ("/api/meritplayers", "/api/serverlog", "/api/changes",
                 "/api/palette", "/api/merit", "/api/audit", "/index", "/monitor")
# Writes worth a line in the audit log, and the verb recorded for each.
AUDITED = {
    "/api/save": "roadmap.save",
    "/api/step-status": "roadmap.step",
    "/api/uat-claim": "uat.claim",
    "/api/uat-result": "uat.result",
    "/api/idea-comment": "idea.comment",
    "/api/regenerate": "roadmap.regenerate",
    "/api/publish": "roadmap.publish",
    "/api/award": "merit.award",
    "/api/revoke": "merit.revoke",
    "/api/uat-award": "merit.uat_award",
    "/api/uat-revoke": "merit.uat_revoke",
    "/api/changes/action": "llm.action",
    "/api/palette/refresh": "palette.refresh",
}
# A save posts the whole document, so these three are the routes that need the
# field-level check as well as the route-level one.
DOCUMENT_WRITES = ("/api/save", "/api/regenerate", "/api/publish")
MAX_BODY = 8 * 1024 * 1024   # the ideas array is large; unbounded is a weapon
# Caps on the two free-text fields a tester can write. Generous enough for a
# real report, small enough that the YAML stays readable and the audit diff
# stays inside DIFF_MAX_LEN.
MAX_RESULT_LEN = 3000
MAX_COMMENT_LEN = 3000


def route_key(path: str) -> str:
    """Normalize a request path to the key ROUTE_CAPS is written in."""
    path = urllib.parse.urlparse(path or "/").path or "/"
    if path in ROUTE_CAPS or path in PUBLIC_ROUTES or path in ANY_USER_ROUTES:
        return path
    for prefix in PREFIX_ROUTES:
        if path.startswith(prefix):
            return prefix
    return path


def changed_summary(posted: list, disk: list, limit: int = 8) -> str:
    """Which ideas this write actually changes, for the audit log.

    "saved the document" is not a useful record when the page posts all ~600
    items every time; the ids that moved are. Both sides are already normalized
    by the caller, so a plain comparison is meaningful.
    """
    before = {i.get("id"): i for i in disk if isinstance(i, dict)}
    after = {i.get("id"): i for i in posted if isinstance(i, dict)}
    touched = [iid for iid in after if before.get(iid) != after[iid]]
    touched += [f"-{iid}" for iid in before if iid not in after]
    if not touched:
        return "no item changes"
    shown = ", ".join(sorted(touched)[:limit])
    return shown + (f" (+{len(touched) - limit} more)" if len(touched) > limit else "")


# --------------------------------------------------------------------------
# Per-field diffs — what actually moved inside an idea
# --------------------------------------------------------------------------
# changed_summary() above records WHICH ideas a write touched. That is the line
# in the audit table; this is what you get when you click the id in it. Nothing
# else can reconstruct it after the fact: write_document() replaces the file
# atomically with no .bak, and a plain /api/save never commits, so a diff not
# captured at write time is gone.
DIFF_MAX_ROWS = 400      # per audit entry; a mass rename must not write 50k rows
DIFF_MAX_LEN = 4000      # per side, characters


def flatten_idea(idea: dict) -> dict:
    """One idea as {field path: scalar}, so a diff can name the exact field.

    The LIST_FIELDS are lists of small mappings, and comparing them whole turns
    "step 3 went todo -> done" into "manual_steps changed" — useless in an audit
    table. Expanding them to `manual_steps[2].status` is the whole point of this
    function; everything else keeps its plain field name.
    """
    out: dict = {}
    for key, val in (idea or {}).items():
        if isinstance(val, list):
            for i, entry in enumerate(val):
                if isinstance(entry, dict):
                    for sub, sval in entry.items():
                        out[f"{key}[{i}].{sub}"] = sval
                else:
                    out[f"{key}[{i}]"] = entry
        else:
            out[key] = val
    return out


def _diff_value(val):
    """One side of a field change, JSON-encoded and capped. None means absent."""
    if val is None:
        return None
    try:
        text = val if isinstance(val, str) else json.dumps(val, ensure_ascii=False)
    except (TypeError, ValueError):
        text = str(val)
    return text[:DIFF_MAX_LEN]


def idea_field_diff(before_ideas, after_ideas,
                    max_rows: int = DIFF_MAX_ROWS) -> list[tuple]:
    """(idea_id, kind, field, before, after) for every field this write moves.

    Both sides are deep-copied and normalized before comparison. Callers hand us
    whatever they happen to have — /api/save posts an already-normalized
    document, _step_write mutates a raw parse — and normalizing only one side
    would report every re-added `blocker: false` as a change the user made.
    """
    before = copy.deepcopy(list(before_ideas or []))
    after = copy.deepcopy(list(after_ideas or []))
    normalize_ideas(before)
    normalize_ideas(after)
    old = {i.get("id"): i for i in before if isinstance(i, dict)}
    new = {i.get("id"): i for i in after if isinstance(i, dict)}

    rows: list[tuple] = []
    truncated = False
    for iid in sorted(set(old) | set(new), key=lambda x: str(x)):
        if truncated:
            break
        a, b = old.get(iid), new.get(iid)
        if a == b:
            continue
        kind = "added" if a is None else "removed" if b is None else "change"
        fa, fb = flatten_idea(a or {}), flatten_idea(b or {})
        for field in sorted(set(fa) | set(fb)):
            if fa.get(field) == fb.get(field):
                continue
            if len(rows) >= max_rows:
                truncated = True
                break
            rows.append((str(iid), kind, field,
                         _diff_value(fa.get(field)), _diff_value(fb.get(field))))
    if truncated:
        rows.append(("", "note", "_truncated", None,
                     f"more than {max_rows} field changes; the rest were not recorded"))
    return rows


def status_label(status: str) -> str:
    """Human label for a status id, for permission-denied messages."""
    meta = STATUS.get(status) or {}
    return meta.get("label") or str(status)


# One connection per thread: sqlite3 objects are not shareable across threads,
# and ThreadingHTTPServer hands every request its own.
_auth_local = threading.local()


def auth_db():
    conn = getattr(_auth_local, "conn", None)
    if conn is None:
        conn = _auth_local.conn = AUTH.connect()
    return conn


# --------------------------------------------------------------------------
# Recent changes — a read-only window onto the audit log
# --------------------------------------------------------------------------
# The audit table is append-only and, until now, was read only by
# bin/roadmap-users.py. "Who published that?" / "who moved this to
# implemented?" is a question the admin and the DMs ask each other in chat, so
# the last week of it belongs in the editor. Read-only on purpose: there is no
# route that writes or prunes audit rows, and there should not be — an audit
# log you can edit from the UI it audits is decoration.
AUDIT_DAYS = 7
AUDIT_MAX_DAYS = 90      # the ceiling on ?days=, so a URL cannot ask for all time
AUDIT_LIMIT = 500        # rows, newest first; a busy week is ~100


def recent_audit(days: int = AUDIT_DAYS) -> dict:
    """The last `days` of audit rows, newest first."""
    since = int(time.time()) - days * 86400
    try:
        rows = AUTH.read_audit(auth_db(), since=since, limit=AUDIT_LIMIT)
    except sqlite3.Error as e:
        return {"available": False, "days": days, "rows": [], "count": 0,
                "truncated": False, "reason": str(e)}
    # Which of these rows have a per-field diff to link to, in one grouped
    # query. Built from the diff table rather than by parsing the detail text:
    # changed_summary() caps that at 8 ids with a "(+N more)" tail, so the text
    # is lossy and this map is not.
    try:
        marks = AUTH.audit_diff_ids(auth_db(), [r.get("id") for r in rows])
    except sqlite3.Error:
        marks = {}
    for r in rows:
        r["diff_ids"] = marks.get(r.get("id"), {})
    return {"available": True, "days": days, "rows": rows, "count": len(rows),
            "truncated": len(rows) >= AUDIT_LIMIT, "limit": AUDIT_LIMIT}


def audit_diff(entry: str, idea: str = "") -> dict:
    """The per-field before/after recorded against one audit entry."""
    try:
        audit_id = int(entry)
    except (TypeError, ValueError):
        return {"ok": False, "rows": [], "reason": "bad entry id"}
    try:
        rows = AUTH.read_audit_diff(auth_db(), audit_id, idea_id=idea)
    except sqlite3.Error as e:
        return {"ok": False, "rows": [], "reason": str(e)}
    return {"ok": True, "entry": audit_id, "idea": idea, "rows": rows,
            "count": len(rows), "keep_days": AUTH.DIFF_KEEP_DAYS}


# --------------------------------------------------------------------------
# HTTP server
# --------------------------------------------------------------------------
class Handler(BaseHTTPRequestHandler):
    # Set by _gate() before any route runs; None means "not logged in".
    user: "AUTH.User | None" = None

    def log_message(self, *a):  # quiet
        pass

    def _send(self, code: int, body: bytes, ctype: str, extra: list | None = None):
        self.send_response(code)
        self.send_header("Content-Type", ctype)
        for name, value in (extra or []):
            self.send_header(name, value)
        # The page IS the app — there is no separate bundle to version. Without
        # this a browser can keep serving an older copy of the editor from cache
        # after a restart, which looks exactly like "the fix didn't work".
        self.send_header("Cache-Control", "no-store, must-revalidate")
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        self.wfile.write(body)

    def _json(self, obj, code: int = 200, extra: list | None = None):
        self._send(code, json.dumps(obj).encode("utf-8"), "application/json", extra)

    # ----------------------------------------------------------------------
    # Authentication and authorization
    # ----------------------------------------------------------------------
    def client_ip(self) -> str:
        """The real client address, for the audit log and the login throttle.

        Behind the Cloudflare Tunnel every request arrives from 127.0.0.1, so
        the socket peer alone would record — and throttle — one address for the
        whole internet. CF-Connecting-IP carries the real one, but it is a
        header, i.e. anything a client cares to type: trust it ONLY when the
        connection really came from loopback, which is the only place the
        tunnel can be.
        """
        peer = (self.client_address or ("", ))[0] or ""
        if peer in ("127.0.0.1", "::1"):
            fwd = (self.headers.get("CF-Connecting-IP") or "").strip()
            if fwd and len(fwd) <= 45 and "\n" not in fwd:
                return fwd
        return peer

    def _cookies(self) -> dict:
        jar = {}
        for part in (self.headers.get("Cookie") or "").split(";"):
            name, _, value = part.partition("=")
            name = name.strip()
            if name:
                jar[name] = value.strip()
        return jar

    def _set_cookie(self, token: str, *, clear: bool = False) -> list:
        bits = [f"{AUTH.SESSION_COOKIE}={token}", "Path=/", "HttpOnly",
                "SameSite=Lax"]
        # The browser talks https to Cloudflare even though this process serves
        # plain http on loopback, so Secure is correct in the deployed shape.
        # Testing against http://localhost directly needs it off.
        if os.environ.get("ROADMAP_AUTH_INSECURE_COOKIE", "") not in ("1", "true"):
            bits.append("Secure")
        bits.append("Max-Age=0" if clear
                    else f"Max-Age={AUTH.SESSION_DAYS * 86400}")
        return [("Set-Cookie", "; ".join(bits))]

    def _resolve_user(self):
        token = self._cookies().get(AUTH.SESSION_COOKIE, "")
        if not token:
            return None
        try:
            return AUTH.resolve_session(auth_db(), token)
        except sqlite3.Error as exc:
            print(f"[warn] auth lookup failed: {exc}", file=sys.stderr)
            return None

    def _deny(self, code: int, message: str, *, wants_html: bool):
        """Refuse a request the way its caller can actually understand.

        A browser hitting a page gets a redirect to the login form; a fetch()
        gets JSON in the shape the editor's existing error banner renders, so
        an expired session reads as "log in again" rather than the bare
        "NetworkError" an unhandled non-200 produces.
        """
        if wants_html and code == 401:
            self.send_response(302)
            self.send_header("Location", "/login")
            self.send_header("Content-Length", "0")
            self.end_headers()
            return
        self._json({"ok": False, "auth": code == 401, "errors": [message],
                    "message": message}, code)

    def _gate(self) -> bool:
        """Resolve the session and check the route's capability.

        Returns True when the request may proceed; otherwise it has already
        answered. Every route goes through here — the table fails closed, so a
        new endpoint that nobody classified is denied rather than exposed.
        """
        path = urllib.parse.urlparse(self.path or "/").path or "/"
        key = route_key(self.path)
        wants_html = not path.startswith("/api/")

        if key in PUBLIC_ROUTES:
            self.user = self._resolve_user()
            return True

        self.user = self._resolve_user()
        if self.user is None:
            self._deny(401, "Your session has expired — please log in again.",
                       wants_html=wants_html)
            return False
        if key in ANY_USER_ROUTES:
            return True

        cap = ROUTE_CAPS.get(key)
        if cap is None:
            # Unknown route. do_GET/do_POST render their own 404s, but a route
            # nobody classified must never reach them with a session attached.
            self._deny(404, "No such endpoint.", wants_html=False)
            return False
        if not self.user.can(cap):
            AUTH.audit(auth_db(), "denied.route", user=self.user,
                       ip=self.client_ip(), detail=f"{self.command} {path} needs {cap}")
            self._deny(403, f"Your role ({AUTH.ROLE_LABELS.get(self.user.role, self.user.role)}) "
                            f"does not have access to this ({cap}).",
                       wants_html=False)
            return False
        return True

    def _step_write(self, payload):
        """Tick one manual_step's status/kind/tester from a queue panel.

        A bookkeeping write, deliberately narrower than /api/save: it re-reads
        roadmap.yaml, touches exactly one step, and never regenerates or commits.
        The queues are used while you are in the toolset or in the game client,
        one step at a time — round-tripping the whole document from a browser tab
        that has been open all afternoon is how you lose someone else's edit.

        The step's own text is the concurrency token: if it no longer matches,
        something moved underneath us and we refuse rather than tick the wrong row.
        """
        iid = payload.get("id")
        try:
            index = int(payload.get("index"))
        except (TypeError, ValueError):
            return self._json({"ok": False, "errors": ["bad step index"]}, 400)

        data = read_yaml()
        ideas = data.get("ideas") or []
        # Baseline complaints, measured on an untouched parse (`ideas` is about
        # to be mutated in place).
        before = {_err_class(e)
                  for e in validate_document(read_yaml().get("ideas") or [])[0]}
        idea = next((i for i in ideas if i.get("id") == iid), None)
        if idea is None:
            return self._json({"ok": False, "errors": [f"no such idea '{iid}'"]}, 404)
        steps = idea.get("manual_steps") or []
        if not 0 <= index < len(steps):
            return self._json({"ok": False, "stale": True,
                               "message": "That step is gone — reload the queue."},
                              409)
        step = steps[index]
        cur_text = step if isinstance(step, str) else str(step.get("step", ""))
        if payload.get("step") is not None and payload["step"] != cur_text:
            return self._json({"ok": False, "stale": True,
                               "message": ("roadmap.yaml changed underneath this "
                                           "queue — reload before ticking.")}, 409)

        step = normalize_step(step)
        steps[index] = step
        if payload.get("status") in STEP_STATUS:
            step["status"] = payload["status"]
        if payload.get("kind") in GEN.STEP_KINDS:
            step["kind"] = payload["kind"]
        if payload.get("tester") is not None:
            tester = str(payload["tester"]).strip()
            if tester:
                step["tester"] = tester
            else:
                step.pop("tester", None)

        # roadmap.yaml carries some long-standing pipeline complaints (a shipped
        # item whose blocker steps aren't finished). Ticking a step must not be
        # the edit that has to fix them, so only errors this write *introduces*
        # are fatal. Compared with the numbers masked out: "…with 6 unfinished
        # blocker manual_step(s)" becoming "…with 5" is this queue working, not
        # a new problem.
        errors, warnings = validate_document(ideas)
        errors = [e for e in errors if _err_class(e) not in before]
        if errors:
            return self._json({"ok": False, "errors": errors})
        write_document(ideas)
        # The page's merge baseline for THIS idea is now one write out of date.
        # Hand back its new fingerprint so the client can rebase it: without
        # that, the next /api/save posts a baseline claiming the idea is
        # untouched while its in-page copy has moved on, and the merge either
        # reverts this write or raises a phantom conflict.
        # Fingerprint the NORMALIZED idea: /api/data hashes ideas after
        # normalize_ideas(), and a raw parse differs from it (an omitted
        # `blocker: false` is re-added, heights are coerced), so hashing the
        # raw dict here would hand back a baseline that never matches.
        fp_idea = copy.deepcopy(idea)
        normalize_ideas([fp_idea])
        return self._json({"ok": True, "version": yaml_version(),
                           "hashes": {iid: _idea_fingerprint(fp_idea)},
                           "warnings": warnings,
                           "message": f"Updated step {index + 1} of '{iid}'."})

    # ----------------------------------------------------------------
    # The tester lane: three narrow writes gated on `uat`
    # ----------------------------------------------------------------
    # A `tester` has no `edit`, so /api/save and /api/step-status are closed to
    # them at the route table. These are the ONLY ways a tester can change
    # roadmap.yaml, and each one patches a single step (or appends a single
    # comment) rather than round-tripping the document. That is what makes the
    # "UAT fields only" ceiling trustworthy without a per-field filter on
    # /api/save -- see the ROLES comment in bin/roadmap_auth.py.
    #
    # Every player-identifying value written here comes from the caller's bound
    # `player_name`, never from the request body: a name off the wire is a name
    # the caller chose, and these names decide who gets paid merit.

    def _actor_player(self):
        """The in-game player name this session speaks for, or ''."""
        return (getattr(self.user, "player_name", "") or "").strip()

    def _need_actor(self):
        """The error response for an account with no bound player name."""
        return self._json({"ok": False, "errors": [
            "Your account is not bound to an in-game player name, so this "
            "cannot be credited to anyone. Ask the admin to run: "
            f"roadmap-users.py player {self.user.username} \"Your Player Name\""
        ]}, 409)

    def _find_step(self, payload, *, uat_only=True):
        """Locate one manual_step for a tester write.

        Returns (ideas, idea, steps, index, step, error_response). The step's own
        text is the concurrency token, exactly as in _step_write: if it no longer
        matches, something moved underneath us and we refuse rather than write to
        the wrong row.
        """
        blank = (None, None, None, None, None)
        iid = payload.get("id")
        try:
            index = int(payload.get("index"))
        except (TypeError, ValueError):
            return blank + (self._json({"ok": False,
                                        "errors": ["bad step index"]}, 400),)
        data = read_yaml()
        ideas = data.get("ideas") or []
        idea = next((i for i in ideas if i.get("id") == iid), None)
        if idea is None:
            return blank + (self._json({"ok": False,
                                        "errors": [f"no such idea '{iid}'"]}, 404),)
        steps = idea.get("manual_steps") or []
        if not 0 <= index < len(steps):
            return blank + (self._json({"ok": False, "stale": True,
                                        "message": "That step is gone — reload "
                                                   "the queue."}, 409),)
        cur = steps[index]
        cur_text = cur if isinstance(cur, str) else str(cur.get("step", ""))
        if payload.get("step") is not None and payload["step"] != cur_text:
            return blank + (self._json({"ok": False, "stale": True,
                                        "message": ("roadmap.yaml changed "
                                                    "underneath this queue — "
                                                    "reload before writing.")}, 409),)
        step = normalize_step(cur)
        steps[index] = step
        idea["manual_steps"] = steps
        if uat_only and step.get("kind") != "uat":
            return blank + (self._json({"ok": False, "errors": [
                "That step is not a UAT check, so there is nothing to test on "
                "it. Only a step with kind: uat can be claimed or reported on."
            ]}, 403),)
        return ideas, idea, steps, index, step, None

    def _finish_tester_write(self, ideas, idea, iid, message):
        """Validate-narrowly, write, and hand back a rebased fingerprint.

        Same contract as the tail of _step_write: roadmap.yaml carries some
        long-standing pipeline complaints, and a tester recording a result must
        not be the write that has to fix them, so only errors this write
        *introduces* are fatal.
        """
        before = {_err_class(e)
                  for e in validate_document(read_yaml().get("ideas") or [])[0]}
        errors, warnings = validate_document(ideas)
        errors = [e for e in errors if _err_class(e) not in before]
        if errors:
            return self._json({"ok": False, "errors": errors})
        write_document(ideas)
        fp_idea = copy.deepcopy(idea)
        normalize_ideas([fp_idea])
        return self._json({"ok": True, "version": yaml_version(),
                           "hashes": {iid: _idea_fingerprint(fp_idea)},
                           "warnings": warnings, "idea": fp_idea,
                           "message": message})

    def _uat_claim(self, payload):
        """Take (or hand back) a UAT step, so two testers don't duplicate work.

        A claim is not a credit: it says "I am running this", nothing more. The
        unpaid uat_credits entry appears only when a result is actually recorded
        (_uat_result), so the list keeps meaning "did the work" rather than
        "intended to".
        """
        me = self._actor_player()
        if not me:
            return self._need_actor()
        ideas, idea, steps, index, step, err = self._find_step(payload)
        if err:
            return err
        iid = idea.get("id")
        held = (step.get("claimed_by") or "").strip()
        if payload.get("release"):
            if held and held.lower() != me.lower() and not self.user.can("edit"):
                return self._json({"ok": False, "errors": [
                    f"That check is claimed by {held}, not you."]}, 409)
            step.pop("claimed_by", None)
            # Only walk the status back if nobody has recorded anything yet;
            # a released step that was already reported on stays reported on.
            if step.get("status") == "wip" and not step.get("tested_by"):
                step["status"] = "open"
            msg = f"Released step {index + 1} of '{iid}'."
        else:
            # An admin or DM can take a check over -- they are the ones who
            # untangle it when a tester claims something and disappears.
            if held and held.lower() != me.lower() and not self.user.can("edit"):
                return self._json({"ok": False, "errors": [
                    f"{held} has already claimed that check. Ask them, or pick "
                    f"another one."]}, 409)
            step["claimed_by"] = me
            if step.get("status") == "open":
                step["status"] = "wip"
            msg = f"You claimed step {index + 1} of '{iid}'."
        return self._finish_tester_write(ideas, idea, iid, msg)

    def _uat_result(self, payload):
        """Record what actually happened when the check was run.

        Writes the step's result and stamps who/when, and adds an UNPAID
        uat_credits entry for the caller. It never sets `awarded` -- that flag
        records a real meritdb payment and is written only by /api/uat-award,
        which is gated on `merit`. This endpoint is the "submit for review"
        half; the admin's UAT Review panel is the other.
        """
        me = self._actor_player()
        if not me:
            return self._need_actor()
        status = payload.get("status")
        # Deliberately not the whole STEP_STATUS vocabulary: a tester reports
        # what they found, they do not reopen work.
        if status not in ("wip", "failed", "done"):
            return self._json({"ok": False, "errors": [
                "A result must be one of: wip (still checking), failed, done."]}, 400)
        result = str(payload.get("result") or "").strip()[:MAX_RESULT_LEN]
        if status in ("failed", "done") and not result:
            return self._json({"ok": False, "errors": [
                "Say what you saw — a pass or a fail with no notes is not "
                "something the admin can review."]}, 400)
        ideas, idea, steps, index, step, err = self._find_step(payload)
        if err:
            return err
        iid = idea.get("id")
        held = (step.get("claimed_by") or "").strip()
        if held and held.lower() != me.lower() and not self.user.can("edit"):
            return self._json({"ok": False, "errors": [
                f"That check is claimed by {held}. Ask them to release it "
                f"before reporting on it."]}, 409)
        step["claimed_by"] = me
        step["status"] = status
        step["tested_by"] = me
        step["tested_on"] = datetime.now().strftime("%Y-%m-%d")
        if result:
            step["result"] = result
        # The unpaid credit the admin reviews. Matching is case-insensitive for
        # the same reason _uat_write's is: the roster spells names how it likes.
        credits = normalize_uat_credits(idea.get(UAT_FIELD) or [])
        if not any(c.get("player", "").strip().lower() == me.lower()
                   for c in credits):
            credits.append({"player": me, "awarded": False, "date": ""})
        idea[UAT_FIELD] = credits
        return self._finish_tester_write(
            ideas, idea, iid,
            f"Recorded your result on step {index + 1} of '{iid}'. "
            f"The admin reviews it before any merit is paid.")

    def _comment_write(self, payload):
        """Append one note to an idea. Append-only, by design.

        There is no route that edits or deletes a comment, which is precisely
        what makes it safe to hand a tester: the worst they can do to the record
        is add to it. `author` and `date` are stamped here, never posted.
        """
        iid = payload.get("id")
        text = str(payload.get("text") or "").strip()[:MAX_COMMENT_LEN]
        if not text:
            return self._json({"ok": False, "errors": ["Write something first."]}, 400)
        author = self._actor_player() or self.user.label
        data = read_yaml()
        ideas = data.get("ideas") or []
        idea = next((i for i in ideas if i.get("id") == iid), None)
        if idea is None:
            return self._json({"ok": False, "errors": [f"no such idea '{iid}'"]}, 404)
        comments = normalize_comments(idea.get(COMMENTS_FIELD) or [])
        comments.append({"author": author,
                         "date": datetime.now().strftime("%Y-%m-%d"),
                         "text": text})
        idea[COMMENTS_FIELD] = comments
        return self._finish_tester_write(ideas, idea, iid,
                                         f"Added your note to '{iid}'.")

    def _uat_write(self, revoke, payload, ideas, groups, players, epics,
                   warnings):
        """Pay (or take back) one player's UAT credit on one idea.

        Same both-or-neither contract as _merit_write: the meritdb counter and
        the `awarded` flag on that uat_credits entry must agree, so if the YAML
        write fails the merit is immediately reversed.

        Unlike a submitter award this is per-ENTRY, not per-idea: an idea can
        carry several validators and each is paid once. The entry's `awarded`
        flag is the idempotence guard — the same thing MERIT_FLAG is for the
        submitter — so a second click can never pay the same person twice.
        """
        problem = merit_db_problem()
        if problem:
            return self._json({"ok": False, "error": f"merit DB unsafe: {problem}"},
                              code=409)

        iid = payload.get("idea_id") or ""
        who = (payload.get("player") or "").strip()
        idea = next((i for i in ideas if i.get("id") == iid), None)
        if idea is None:
            return self._json({"ok": False,
                               "errors": [f"idea '{iid}' not found in payload"]})
        credits = idea.get(UAT_FIELD) or []
        entry = next((c for c in credits
                      if str(c.get("player", "")).strip().lower() == who.lower()),
                     None)
        if entry is None:
            return self._json({"ok": False,
                               "errors": [f"'{who}' is not a UAT validator on "
                                          f"'{iid}'"]})
        if revoke and not entry.get("awarded"):
            return self._json({"ok": False,
                               "errors": [f"'{who}' has no awarded UAT credit on "
                                          f"'{iid}' to take back"]})
        if not revoke and entry.get("awarded"):
            return self._json({"ok": False,
                               "errors": [f"'{who}' was already paid for "
                                          f"validating '{iid}'"]})

        cdkey = (payload.get("cdkey") or "").strip()
        res = award_merit(who, "", iid, cdkey=cdkey, revoke=revoke, kind="uat")
        if not res.get("ok"):
            # Nothing was paid, so the flag stays as it was; the rest of the
            # form is still saved, exactly as _merit_write does.
            write_document(ideas, groups, players, epics)
            return self._json({
                "ok": False, "warnings": warnings, "version": yaml_version(),
                "matched": res.get("matched"), "reverted": True,
                "errors": [res.get("reason", "merit update failed"),
                           "Your other edits were saved."]})

        if revoke:
            entry.pop("awarded", None)
            entry.pop("date", None)
        else:
            entry["awarded"] = True
            entry["date"] = datetime.now().strftime("%Y-%m-%d")
        try:
            write_document(ideas, groups, players, epics)
        except Exception as e:
            back = award_merit(who, "", iid, cdkey=res.get("cdkey", ""),
                               revoke=not revoke, kind="uat")
            undo = (" Merit change was rolled back."
                    if back.get("ok")
                    else f" MERIT NOT ROLLED BACK: {back.get('reason')}")
            return self._json({"ok": False, "version": yaml_version(),
                               "errors": [f"could not write roadmap.yaml: {e}"
                                          + undo]})
        if res.get("cdkey") and cdkey and who:
            write_merit_alias(who, res["cdkey"])
        return self._json({"ok": True, "warnings": warnings,
                           "version": yaml_version(),
                           "message": res.get("message", "Saved.")})

    def _merit_write(self, revoke, payload, ideas, groups, players, epics,
                     warnings):
        """Move an idea into/out of 'merit awarded' AND pay/take back the merit.

        The two halves must agree, so either both land or neither does:
          * merit fails  -> the idea's status is put back to `prev_status` and
            the flag left alone, but the document is still written, so every
            other edit made in the same form survives (the roadmap is not the
            thing that failed).
          * merit lands but the YAML write blows up -> the merit is immediately
            taken back again, so the DB never records a payment the roadmap
            has no memory of.

        Both halves assume the merit DB is the SHARED, cross-season one. That
        is checked here rather than assumed: writing merit into a per-season
        file succeeds, reports success, and is discarded at the next cutover
        (see merit_db_problem).
        """
        problem = merit_db_problem()
        if problem:
            return self._json({"ok": False, "error": f"merit DB unsafe: {problem}"},
                              code=409)

        iid = payload.get("idea_id") or ""
        idea = next((i for i in ideas if i.get("id") == iid), None)
        if idea is None:
            return self._json({"ok": False,
                               "errors": [f"idea '{iid}' not found in payload"]})
        name = (idea.get("player") or "").strip()
        itype = idea.get("type") or ""
        cdkey = (payload.get("cdkey") or "").strip()
        # skip_merit = admin/community item the user chose to mark awarded with
        # no payment; already-flagged = re-entering `awarded`, never pay twice.
        skip = bool(payload.get("skip_merit"))
        if not revoke and idea.get(MERIT_FLAG):
            skip = True
        if revoke and not idea.get(MERIT_FLAG):
            return self._json({"ok": False,
                               "errors": [f"'{iid}' is not marked as merit awarded"]})

        res = ({"ok": True, "message": "Status changed; no merit granted."}
               if skip and not revoke
               else award_merit(name, itype, iid, cdkey=cdkey, revoke=revoke))
        if not res.get("ok"):
            if not revoke:
                idea["status"] = payload.get("prev_status") or idea.get("status")
                idea.pop(MERIT_FLAG, None)
            write_document(ideas, groups, players, epics)
            return self._json({
                "ok": False, "warnings": warnings, "version": yaml_version(),
                "matched": res.get("matched"), "reverted": not revoke,
                "errors": [res.get("reason", "merit update failed")]
                + (["Status left unchanged; your other edits were saved."]
                   if not revoke else ["Your other edits were saved."])})

        if revoke:
            idea.pop(MERIT_FLAG, None)
        elif not skip:
            idea[MERIT_FLAG] = True
        try:
            write_document(ideas, groups, players, epics)
        except Exception as e:
            undo = ""
            if res.get("cdkey"):
                back = award_merit(name, itype, iid, cdkey=res["cdkey"],
                                   revoke=not revoke)
                undo = (" Merit change was rolled back."
                        if back.get("ok")
                        else f" MERIT NOT ROLLED BACK: {back.get('reason')}")
            return self._json({"ok": False, "version": yaml_version(),
                               "errors": [f"could not write roadmap.yaml: {e}"
                                          + undo]})
        if res.get("cdkey") and cdkey and name:
            # A hand-picked player teaches the matcher for next time.
            write_merit_alias(name, res["cdkey"])
        return self._json({"ok": True, "warnings": warnings,
                           "version": yaml_version(),
                           "message": res.get("message", "Saved.")})

    def do_GET(self):
        if not self._gate():
            return
        if self.path == "/login" or self.path.startswith("/login?"):
            # Already signed in? Nothing to do here.
            if self.user is not None:
                self.send_response(302)
                self.send_header("Location", "/")
                self.send_header("Content-Length", "0")
                self.end_headers()
                return
            self._send(200, LOGIN_PAGE.encode("utf-8"), "text/html; charset=utf-8")
        elif self.path == "/api/me":
            self._json({"ok": True, "me": self.user.public()})
        elif self.path == "/" or self.path.startswith("/index"):
            self._send(200, PAGE.encode("utf-8"), "text/html; charset=utf-8")
        elif self.path == "/monitor" or self.path.startswith("/monitor?"):
            self._send(200, MONITOR_PAGE.encode("utf-8"),
                       "text/html; charset=utf-8")
        elif self.path.startswith("/api/serverlog"):
            q = urllib.parse.parse_qs(urllib.parse.urlparse(self.path).query)
            try:
                tail = max(1, min(2000, int(q.get("tail", ["400"])[0])))
            except ValueError:
                tail = 400
            # All realms at once now (bin/watch-all-servers' web twin), so the
            # per-realm status lives in `realms` and every line carries the tag
            # it came from. MONITOR_PAGE is the only consumer.
            raw = q.get("raw", ["0"])[0] not in ("", "0", "false")
            status, lines = server_log_tail_all(tail, raw=raw)
            self._json({"ok": any(r["ok"] for r in status),
                        "realms": status, "lines": lines})
        elif self.path == "/api/data":
            data = read_yaml()
            ideas = data.get("ideas", []) or []
            # base_hashes is the client's merge baseline. It is computed here,
            # server-side, and the browser only stores and echoes it back — see
            # the fingerprint section above for why it is never hashed in JS.
            normalize_ideas(ideas)
            self._json({"ideas": ideas, "vocab": vocab(data),
                        "base_hashes": fingerprints(ideas),
                        "base_vocab": vocab_fingerprints(data),
                        "version": yaml_version(),
                        # Who is asking. The page hides controls it may not use;
                        # the server enforces the same rules regardless.
                        "me": self.user.public()})
        elif self.path == "/api/version":
            self._json({"version": yaml_version()})
        elif self.path == "/api/meritplayers":
            # Must precede the /api/merit prefix test below, which would
            # otherwise swallow this path.
            self._json(merit_players())
        elif self.path.startswith("/api/merit"):
            q = urllib.parse.urlparse(self.path).query
            player = urllib.parse.parse_qs(q).get("player", [""])[0]
            self._json(merit_for_player(player))
        elif self.path == "/api/pending":
            self._json(pending_requests())
        elif self.path.startswith("/api/audit/diff"):
            # Covered by the "/api/audit" PREFIX_ROUTES entry, so it inherits
            # the audit_view capability with no ROUTE_CAPS edit.
            q = urllib.parse.parse_qs(urllib.parse.urlparse(self.path).query)
            self._json(audit_diff(q.get("entry", [""])[0], q.get("idea", [""])[0]))
        elif self.path.startswith("/api/audit"):
            q = urllib.parse.parse_qs(urllib.parse.urlparse(self.path).query)
            try:
                days = max(1, min(AUDIT_MAX_DAYS, int(q.get("days", [""])[0])))
            except ValueError:
                days = AUDIT_DAYS
            self._json(recent_audit(days))
        elif self.path.startswith("/api/changes"):
            if REVIEW is None:
                return self._json({"groups": [], "batches": [], "tasks": [],
                                   "total": 0, "pending": 0, "shown": 0,
                                   "unavailable": True})
            q = urllib.parse.parse_qs(urllib.parse.urlparse(self.path).query)
            done = q.get("done", ["0"])[0] == "1"
            if q.get("mode", [""])[0] == "compare":
                self._json(REVIEW.compare_payload(show_done=done))
            else:
                self._json(REVIEW.payload(show_done=done, task=q.get("task", [""])[0]))
        elif self.path.startswith("/api/palette"):
            q = urllib.parse.urlparse(self.path).query
            term = urllib.parse.parse_qs(q).get("q", [""])[0]
            self._json(search_palette(term))
        else:
            self._send(404, b"not found", "text/plain")

    def _read_body(self) -> dict:
        n = int(self.headers.get("Content-Length", 0) or 0)
        if n > MAX_BODY:
            # The ideas array is genuinely large, but an unbounded read is a
            # remote memory-exhaustion primitive now that this is reachable
            # from outside the LAN.
            raise ValueError(f"request body too large ({n} bytes)")
        return json.loads(self.rfile.read(n) or b"{}")

    def _csrf_ok(self) -> bool:
        """Reject a cross-site write.

        The session cookie is SameSite=Lax, which already stops this, but Lax
        is one browser default away from being the only thing standing between
        a page the admin happens to visit and a `git push`. Two cheap belts:

        * Require JSON. A cross-origin <form> can only send text/plain,
          multipart/form-data or urlencoded — never application/json without a
          preflight, which this server never approves. _read_body used to parse
          any body regardless of its declared type, which made that gap real.
        * Honour Sec-Fetch-Site / Origin when the browser sends them.
        """
        ctype = (self.headers.get("Content-Type") or "").split(";")[0].strip().lower()
        if ctype != "application/json":
            return False
        site = (self.headers.get("Sec-Fetch-Site") or "").strip().lower()
        if site and site not in ("same-origin", "same-site", "none"):
            return False
        origin = (self.headers.get("Origin") or "").strip()
        if origin:
            host = (self.headers.get("Host") or "").strip()
            forwarded = (self.headers.get("X-Forwarded-Host") or "").strip()
            allowed = {h.lower() for h in (host, forwarded) if h}
            if urllib.parse.urlparse(origin).netloc.lower() not in allowed:
                return False
        return True

    def _do_login(self):
        ip = self.client_ip()
        try:
            payload = self._read_body()
        except Exception:
            return self._json({"ok": False, "message": "Bad request."}, 400)
        username = str(payload.get("username") or "").strip().lower()
        password = str(payload.get("password") or "")
        conn = auth_db()

        if AUTH.user_count(conn) == 0:
            # Nothing to log in to yet. Say so plainly rather than let the
            # operator conclude they have forgotten a password that was never set.
            return self._json({"ok": False, "setup": True,
                               "message": AUTH.bootstrap_hint()}, 503)

        wait = AUTH.throttle_check(ip, username)
        if wait:
            AUTH.audit(conn, "login.throttled", username=username, ip=ip,
                       detail=f"{wait}s remaining")
            mins = max(1, wait // 60)
            return self._json({"ok": False, "message":
                               f"Too many failed attempts. Try again in about "
                               f"{mins} minute{'s' if mins != 1 else ''}."}, 429)

        user = AUTH.authenticate(conn, username, password)
        if user is None:
            AUTH.throttle_fail(ip, username)
            AUTH.audit(conn, "login.fail", username=username, ip=ip)
            # One message for every failure mode: no username oracle.
            return self._json({"ok": False,
                               "message": "Incorrect username or password."}, 401)

        AUTH.throttle_clear(ip, username)
        token = AUTH.create_session(conn, user.username, ip=ip,
                                    user_agent=self.headers.get("User-Agent", ""))
        AUTH.audit(conn, "login.ok", user=user, ip=ip)
        AUTH.purge_expired_sessions(conn)
        return self._json({"ok": True, "me": user.public()},
                          extra=self._set_cookie(token))

    def _do_logout(self):
        token = self._cookies().get(AUTH.SESSION_COOKIE, "")
        if token:
            AUTH.revoke_session(auth_db(), token)
        AUTH.audit(auth_db(), "logout", user=self.user, ip=self.client_ip())
        return self._json({"ok": True}, extra=self._set_cookie("", clear=True))

    def do_POST(self):
        """Serialize every POST that can write roadmap.yaml.

        The lock is held for the whole read→merge→validate→write cycle, closing
        the window in which an external write could land between the read a
        merge was computed from and the os.replace() that commits it.
        """
        if not self._csrf_ok():
            return self._json({"ok": False, "errors": [
                "Request rejected: this endpoint only accepts same-origin JSON."]},
                403)
        if not self._gate():
            return
        # Nothing may inherit the previous request's audit entry: threads are
        # reused, and a stale id would file this write's diff under someone
        # else's line in the audit table.
        arm_audit_diff(None)
        path = urllib.parse.urlparse(self.path or "/").path
        if path == "/api/login":
            return self._do_login()
        if path == "/api/logout":
            return self._do_logout()
        try:
            # Neither of these touches roadmap.yaml, so neither needs the lock.
            if self.path in ("/api/palette/refresh", "/api/changes/action"):
                return self._do_POST_locked()
            with yaml_lock(timeout=60.0):
                return self._do_POST_locked()
        except TimeoutError as e:
            return self._json({"ok": False, "errors": [f"roadmap.yaml is busy: {e}"]},
                              503)
        except Exception:
            # Never let an unhandled exception kill the connection: the browser
            # reports that only as a bare "NetworkError", with the real cause
            # buried in the service journal. Hand back the traceback's last line
            # so the banner names what actually broke.
            tb = traceback.format_exc()
            print(tb, file=sys.stderr)
            last = tb.strip().splitlines()[-1]
            # The detail is for the person who can act on it. An unauthenticated
            # caller gets the fact of the failure and nothing about the internals.
            detail = ([f"server error handling {self.path}: {last}",
                       "Nothing was written. The full traceback is in the service "
                       "log (journalctl --user -u roadmap-editor)."]
                      if self.user is not None
                      else ["Server error. Nothing was written."])
            return self._json({"ok": False, "errors": detail}, 500)

    def _audit_write(self, detail: str = "") -> None:
        """Record one mutating request against the caller.

        Logged at the point the request is accepted rather than after it
        succeeds: a write that then failed validation is exactly as interesting
        to a later reader as one that landed, and threading a log call through
        every return site in this method would be a lot of edits for a worse
        record. Refusals are logged separately as denied.* entries.
        """
        action = AUDITED.get(urllib.parse.urlparse(self.path or "").path)
        if action:
            audit_id = AUTH.audit(auth_db(), action, user=self.user,
                                  ip=self.client_ip(), detail=detail)
            # Every mutating route reaches roadmap.yaml through write_document(),
            # so arming here covers save/regenerate/publish, both merit pairs and
            # the queue's step tick without instrumenting each of their several
            # write call sites -- and covers the next route added for free.
            arm_audit_diff(audit_id)

    def _do_POST_locked(self):
        # Palette-map refresh needs no body/validation: rerun the standalone
        # generator and hand back its summary. Never touches the roadmap or git.
        if self.path == "/api/palette/refresh":
            self._audit_write()
            ok, output = refresh_palette_map()
            return self._json({"ok": ok, "output": output,
                               "built": load_palette_map()["built"],
                               "message": ("Palette map rebuilt."
                                           if ok else "Palette map refresh FAILED.")})
        if self.path == "/api/changes/action":
            if REVIEW is None:
                return self._json({"ok": False,
                                   "message": "the bin/llm harness is not installed"})
            try:
                body = self._read_body()
            except Exception as e:
                return self._json({"ok": False, "message": f"bad request: {e}"}, 400)
            self._audit_write(f"{body.get('action', '?')} "
                              f"{body.get('id') or body.get('group') or ''}".strip())
            return self._json(REVIEW.act(body))
        if self.path == "/api/step-status":
            try:
                payload = self._read_body()
            except Exception as e:
                return self._json({"ok": False, "errors": [f"bad request: {e}"]}, 400)
            self._audit_write(f"{payload.get('id')} step #{payload.get('index')} "
                              f"-> {payload.get('status')}")
            return self._step_write(payload)
        if self.path in ("/api/uat-claim", "/api/uat-result", "/api/idea-comment"):
            try:
                payload = self._read_body()
            except Exception as e:
                return self._json({"ok": False, "errors": [f"bad request: {e}"]}, 400)
            if self.path == "/api/uat-claim":
                self._audit_write(f"{payload.get('id')} step #{payload.get('index')}"
                                  f" {'released' if payload.get('release') else 'claimed'}")
                return self._uat_claim(payload)
            if self.path == "/api/uat-result":
                self._audit_write(f"{payload.get('id')} step #{payload.get('index')}"
                                  f" result -> {payload.get('status')}")
                return self._uat_result(payload)
            self._audit_write(f"{payload.get('id')} comment")
            return self._comment_write(payload)
        try:
            payload = self._read_body()
        except Exception as e:
            return self._json({"ok": False, "errors": [f"bad request: {e}"]}, 400)
        ideas = payload.get("ideas", [])
        groups = payload.get("groups")
        players = payload.get("players")
        epics = payload.get("epics")
        base_version = payload.get("base_version")
        base_hashes = payload.get("base_hashes")
        force = bool(payload.get("force"))
        # Normalize before anything compares these ideas to what is on disk —
        # the disk copy is already in stored form (see normalize_ideas).
        normalize_ideas(ideas, groups)
        # Anti-clobber. The file changing on disk is NOT by itself a conflict:
        # an agent editing some other item is the common case, and refusing the
        # write there is what forced the admin to reload and redo their edits.
        # So when the client sent a fingerprint baseline we three-way merge, and
        # only a genuine same-idea collision is reported as a conflict.
        if (base_version is not None and not force
                and base_version != yaml_version()):
            disk = read_yaml()
            disk_ideas = disk.get("ideas") or []
            if not isinstance(base_hashes, dict):
                # An old tab with no baseline: nothing to merge against, so fall
                # back to the original all-or-nothing prompt.
                return self._json({
                    "ok": False, "conflict": True, "version": yaml_version(),
                    "message": ("roadmap.yaml changed on disk since you opened "
                                "it (external edit detected). Reload to pull "
                                "those changes, or Force save to overwrite "
                                "them.")})
            normalize_ideas(disk_ideas)
            merged, overlap = merge_ideas(base_hashes, ideas, disk_ideas)
            if overlap:
                names = ", ".join(overlap[:5]) + ("…" if len(overlap) > 5 else "")
                return self._json({
                    "ok": False, "conflict": True, "version": yaml_version(),
                    "overlap": overlap,
                    "message": (f"roadmap.yaml changed on disk and the same "
                                f"item(s) were edited on both sides: {names}. "
                                f"Reload to pull those changes, or Force save "
                                f"to overwrite them.")})
            ideas = merged
            # Same rule for the small vocab blocks: one the client did not touch
            # must come from disk, not from its stale copy, or the merge would
            # silently revert an external edit to the group/player/epic lists.
            base_vocab = payload.get("base_vocab") or {}
            disk_vocab = vocab(disk)
            posted = {"groups": groups, "players": players, "epics": epics}
            for key in ("groups", "players", "epics"):
                if posted[key] is None:
                    continue
                unchanged_by_us = (base_vocab.get(key) ==
                                   block_fingerprint(posted[key]))
                if unchanged_by_us:
                    posted[key] = disk_vocab.get(key) or []
            groups, players, epics = (posted["groups"], posted["players"],
                                      posted["epics"])
        errors, warnings = validate_document(ideas, groups, players, epics)
        if errors:
            return self._json({"ok": False, "errors": errors, "warnings": warnings})

        # Route gating is not enough here. The page posts the ENTIRE ideas array
        # on every save, and the write path below stores what it is given — so
        # without this a role that cannot reach /api/award could still promote
        # an item to `implemented`, or set merit_awarded, through /api/save.
        # Read the on-disk document for the comparison: we hold yaml_lock, so
        # this is the same state the write is about to replace.
        if self.path in DOCUMENT_WRITES:
            disk_ideas = read_yaml().get("ideas") or []
            normalize_ideas(disk_ideas)
            denied = AUTH.enforce_idea_permissions(
                self.user.caps, ideas, disk_ideas, status_label=status_label)
            if denied:
                AUTH.audit(auth_db(), "denied.field", user=self.user,
                           ip=self.client_ip(),
                           detail=f"{self.path}: {denied[0]}")
                return self._json({"ok": False, "errors": denied,
                                   "warnings": warnings,
                                   "version": yaml_version()}, 403)
            self._audit_write(changed_summary(ideas, disk_ideas))
        else:
            self._audit_write(str(payload.get("idea_id") or ""))

        if self.path == "/api/save":
            write_document(ideas, groups, players, epics)
            return self._json({"ok": True, "warnings": warnings,
                               "version": yaml_version(),
                               "message": "Saved roadmap.yaml."})
        if self.path in ("/api/award", "/api/revoke"):
            return self._merit_write(self.path == "/api/revoke", payload, ideas,
                                     groups, players, epics, warnings)
        if self.path in ("/api/uat-award", "/api/uat-revoke"):
            return self._uat_write(self.path == "/api/uat-revoke", payload, ideas,
                                   groups, players, epics, warnings)
        if self.path == "/api/regenerate":
            write_document(ideas, groups, players, epics)
            stamp = stamp_as_of()
            ok, output = regenerate()
            return self._json({"ok": ok, "warnings": warnings, "output": output,
                               "version": yaml_version(),
                               "message": (f"Saved + regenerated Roadmap.html (as of {stamp})."
                                           if ok else "Regenerate FAILED.")})
        if self.path == "/api/publish":
            write_document(ideas, groups, players, epics)
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
                _, db_msg = sync_recent_updates_db(ideas, groups, epics)
            except Exception as e:
                db_msg = f"DB sync FAILED (wiki still published): {e}"
            steps.append(db_msg)
            git_ok, git_msg = git_publish()
            steps.append(git_msg)
            # And into the LIVE season's wiki, so a player sees the change on
            # homerslotr.com now rather than at the next promotion. Non-fatal
            # for the same reason the DB sync is: this realm's publish already
            # succeeded, and a second repo's problem must not report it as
            # failed. Its own message says what happened.
            try:
                live_ok, live_msg = publish_to_live_realm(roadmap_body())
            except Exception as e:
                live_ok, live_msg = False, f"live realm publish FAILED: {e}"
            steps.append(live_msg)
            if git_ok:
                message = ("Published to wiki + pushed to git."
                           if live_ok else
                           "Published here; the LIVE wiki did NOT update — see output.")
            else:
                message = "Publish/push FAILED."
            return self._json({"ok": git_ok, "warnings": warnings,
                               "version": yaml_version(),
                               "output": "\n".join(steps),
                               "message": message})
        return self._json({"ok": False, "errors": ["unknown endpoint"]}, 404)


# --------------------------------------------------------------------------
# Browser UI (single inline page, no build step, no external deps)
# --------------------------------------------------------------------------
# Live server-log monitor — the web equivalent of `bin/watch-all-servers`, and
# filtered by the same blocklist (bin/server-log-noise.txt), so the two monitors
# never disagree about what a clean log looks like. Black terminal-style page
# that polls /api/serverlog and rides through restarts. Every realm on the box
# is interleaved into one chronological stream, each line tagged and coloured by
# realm; the realm checkboxes filter client-side, "show all" re-fetches with the
# noise filter off.
MONITOR_PAGE = r"""<!doctype html>
<html lang="en"><head><meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<title>Server Monitor — Homer's LotR</title>
<style>
  html, body { margin:0; height:100%; background:#000; color:#c8c8c8;
    font:13px/1.5 ui-monospace, "SF Mono", Menlo, Consolas, monospace; }
  #bar { position:sticky; top:0; display:flex; align-items:center; gap:14px;
    padding:8px 14px; background:#0a0a0a; border-bottom:1px solid #1e1e1e;
    flex-wrap:wrap; }
  #bar h1 { margin:0; font-size:13px; font-weight:600; color:#9ecbff;
    letter-spacing:.02em; }
  label { color:#7d7d7d; cursor:pointer; white-space:nowrap; }
  .realm { display:inline-flex; align-items:center; gap:5px; }
  .realm .dot::before { content:"●"; }
  .realm .dot.up { color:#3fb950; } .realm .dot.down { color:#f85149; }
  #err { color:#f85149; }
  #log { padding:12px 14px; }
  /* One row per line: time, tag, message. The realm colour is set inline from
     the API so the terminal monitor and this page never drift apart. */
  .ln { display:flex; gap:8px; white-space:pre-wrap; word-break:break-word;
        border-left:2px solid transparent; padding-left:6px; }
  .ln .t { color:#4d4d4d; flex:none; }
  .ln .g { flex:none; font-weight:600; }
  .ln .m { flex:1 1 auto; }
  /* Severity is a stripe + weight, never a text colour — the text colour is
     already carrying which realm the line came from. */
  .ln.err   { border-left-color:#f85149; font-weight:600; }
  .ln.warn  { border-left-color:#d29922; font-weight:600; }
  .ln.join  { border-left-color:#3fb950; }
  .ln.leave { border-left-color:#d29922; }
  .ln.dm    { border-left-color:#9ecbff; }
</style></head>
<body>
  <div id="bar">
    <h1>Homer's LotR — Server Monitor (all realms)</h1>
    <span id="realms">connecting…</span>
    <span id="err"></span>
    <label style="margin-left:auto"
           title="Show every line the servers print, including the ~95% of
boilerplate the blocklist in bin/server-log-noise.txt normally hides.">
      <input type="checkbox" id="raw"> show all</label>
    <label><input type="checkbox" id="auto" checked>
      auto-scroll</label>
  </div>
  <div id="log">Loading server logs…</div>
<script>
const logEl = document.getElementById('log');
const realmsEl = document.getElementById('realms');
const errEl = document.getElementById('err');
const autoEl = document.getElementById('auto');
const rawEl = document.getElementById('raw');
const esc = s => s.replace(/&/g,'&amp;').replace(/</g,'&lt;').replace(/>/g,'&gt;');
// Which realms are shown. Survives polls; a realm seen for the first time
// defaults to visible.
const shown = {};
let colors = {}, tagW = 3;
// Signatures of what is already on screen. A poll that changes nothing must not
// touch the DOM at all: rewriting innerHTML every 3s threw away the reader's
// text selection and (with the old unconditional scrollTo) yanked the view back
// to the bottom while they were reading something further up.
let lastLogSig = null, lastBarSig = null, firstPaint = true, forceBottom = false;

// The server's own severity letter beats guessing from the words; W/E lines are
// also the ones the noise filter never drops, so they should look different.
// Largest scrollY the document allows. body vs documentElement disagree
// depending on the `height:100%` above, so take whichever is taller.
const maxScroll = () => Math.max(document.documentElement.scrollHeight,
                                 document.body.scrollHeight) - window.innerHeight;

function severity(line, sev) {
  if (sev === 'E') return 'err';
  if (sev === 'W') return 'warn';
  if (/error|exception|fail|traceback/i.test(line)) return 'err';
  if (/join|enter|added to|logged in|connect/i.test(line)) return 'join';
  if (/leav|left|remov|drop|disconnect|logout/i.test(line)) return 'leave';
  if (/\bDM\b|dungeon master/i.test(line)) return 'dm';
  return '';
}

function renderBar(realms) {
  // Rebuilding the checkboxes on every tick steals focus mid-click.
  const sig = JSON.stringify(realms.map(r => [r.tag, r.ok, r.color, r.label]));
  if (sig === lastBarSig) return;
  lastBarSig = sig;
  realmsEl.innerHTML = realms.map(r => {
    if (!(r.tag in shown)) shown[r.tag] = true;
    return `<span class="realm" title="${esc(r.label)} — ${esc(r.container)}">`
      + `<span class="dot ${r.ok ? 'up' : 'down'}"></span>`
      + `<label><input type="checkbox" data-tag="${esc(r.tag)}"`
      + `${shown[r.tag] ? ' checked' : ''}> `
      + `<span style="color:${esc(r.color)};font-weight:600">${esc(r.tag)}</span>`
      + `</label></span>`;
  }).join(' ');
  realmsEl.querySelectorAll('input[data-tag]').forEach(cb => {
    cb.onchange = () => { shown[cb.dataset.tag] = cb.checked; applyFilter(); };
  });
}

function applyFilter() {
  logEl.querySelectorAll('.ln').forEach(el => {
    const t = el.dataset.tag;
    el.style.display = (!t || shown[t] !== false) ? '' : 'none';
  });
}

async function poll() {
  try {
    const r = await fetch('/api/serverlog?tail=600'
                          + (rawEl.checked ? '&raw=1' : ''), {cache:'no-store'});
    // An expired session here would otherwise render as a silent stall.
    if (r.status === 401){ location.href = '/login'; return; }
    if (r.status === 403){
      errEl.textContent = 'Your role does not have access to the server log.';
      return;
    }
    const d = await r.json();
    colors = {}; tagW = 3;
    (d.realms || []).forEach(x => { colors[x.tag] = x.color;
                                    tagW = Math.max(tagW, x.tag.length); });
    renderBar(d.realms || []);
    errEl.textContent = (d.realms || []).length ? '' : 'no realms found';
    // Was the reader parked at the tail? Measure BEFORE the DOM changes, with
    // the same metric the scroll below uses, so "at the bottom" and "go to the
    // bottom" can't disagree. 4px of slack absorbs sub-pixel layout and zoom.
    // Scrolling back down silently re-arms following; scrolling up disarms it.
    const atBottom = window.scrollY >= maxScroll() - 4;
    const html = (d.lines || []).map(l => {
      const tag = (l.tag || '').padEnd(tagW);
      const col = colors[l.tag] || '#c8c8c8';
      const sev = severity(l.text || '', l.sev || '');
      return `<div class="ln ${sev}" data-tag="${esc(l.tag || '')}">`
        + `<span class="t">${esc(l.time || '')}</span>`
        + `<span class="g" style="color:${esc(col)}">${l.tag ? '[' + esc(tag) + ']' : ''}</span>`
        + `<span class="m" style="color:${esc(col)}">${esc(l.text || '')}</span></div>`;
    }).join('');
    if (html === lastLogSig && !forceBottom) return;   // nothing new happened
    lastLogSig = html;
    logEl.innerHTML = html;
    applyFilter();
    // Jump to the bottom only when there is no reading position to protect:
    // the first paint, or a "show all" flip that replaced the whole buffer.
    if (firstPaint || forceBottom || (autoEl.checked && atBottom)) {
      window.scrollTo(0, maxScroll());
    }
    firstPaint = false; forceBottom = false;
  } catch (e) {
    errEl.textContent = 'monitor unreachable';
  }
}
poll();
// don't make the admin wait out the interval, and land at the tail afterwards
rawEl.onchange = () => { forceBottom = true; poll(); };
setInterval(poll, 3000);
</script>
</body></html>"""


LOGIN_PAGE = r"""<!doctype html>
<html lang="en"><head><meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<title>Sign in — Roadmap Editor</title>
<style>
  :root { --bg:#1e2127; --panel:#272b33; --ink:#e6e6e6; --mut:#9aa3af;
          --line:#3a3f4a; --accent:#6ea8fe; --err:#ff6b6b; }
  * { box-sizing:border-box; }
  body { margin:0; font:14px/1.45 system-ui,sans-serif; background:var(--bg);
         color:var(--ink); min-height:100vh; display:flex; align-items:center;
         justify-content:center; padding:20px; }
  form { background:var(--panel); border:1px solid var(--line); border-radius:10px;
         padding:26px 24px; width:100%; max-width:340px; }
  h1 { font-size:17px; margin:0 0 2px; }
  .sub { color:var(--mut); font-size:12px; margin:0 0 18px; }
  label { display:block; margin:12px 0 4px; color:var(--mut); font-size:12px; }
  input { width:100%; padding:9px 10px; background:var(--bg); color:var(--ink);
          border:1px solid var(--line); border-radius:6px; font:inherit; }
  input:focus { outline:none; border-color:var(--accent); }
  button { width:100%; margin-top:18px; padding:9px; border-radius:6px;
           border:1px solid var(--accent); background:var(--accent); color:#12161c;
           font:inherit; font-weight:600; cursor:pointer; }
  button:disabled { opacity:.6; cursor:default; }
  #msg { margin-top:14px; color:var(--err); font-size:12px; white-space:pre-wrap;
         display:none; }
  #msg.show { display:block; }
  .foot { margin-top:16px; color:var(--mut); font-size:11px; line-height:1.5; }
</style></head><body>
<form id="f" autocomplete="on">
  <h1>Roadmap Editor</h1>
  <p class="sub">Homer&rsquo;s LotR &mdash; dev roadmap &amp; merit backlog</p>
  <label for="u">Username</label>
  <input id="u" name="username" autocomplete="username" autocapitalize="none"
         autocorrect="off" spellcheck="false" required autofocus>
  <label for="p">Password</label>
  <input id="p" name="password" type="password" autocomplete="current-password" required>
  <button id="go" type="submit">Sign in</button>
  <div id="msg"></div>
  <p class="foot">Accounts are created on the server by the administrator.
     There is no self-service signup or password reset.</p>
</form>
<script>
const msg = document.getElementById('msg');
const go  = document.getElementById('go');
document.getElementById('f').addEventListener('submit', async (e) => {
  e.preventDefault();
  msg.classList.remove('show');
  go.disabled = true; go.textContent = 'Signing in…';
  let res;
  try {
    const r = await fetch('/api/login', {
      method:'POST', headers:{'Content-Type':'application/json'},
      body: JSON.stringify({username: document.getElementById('u').value,
                            password: document.getElementById('p').value})});
    res = await r.json();
  } catch (err) {
    res = {ok:false, message:'Could not reach the server. Is it running?'};
  }
  if (res.ok){ location.href = '/'; return; }
  go.disabled = false; go.textContent = 'Sign in';
  document.getElementById('p').value = '';
  document.getElementById('p').focus();
  msg.textContent = res.message || 'Sign-in failed.';
  msg.classList.add('show');
});
</script>
</body></html>
"""


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
  .tbadge.uat         { background:#1f4038; color:#b0e6d4; border-color:#2f6455; }
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
  .rt-rich { min-height:96px; overflow:auto; resize:vertical;
             padding:7px 9px; background:var(--bg); color:var(--ink);
             border:1px solid var(--line); border-radius:6px; outline:none; }
  .rt-rich:focus { border-color:var(--accent); }
  .rt-rich ul, .rt-rich ol { margin:0.3em 0; padding-left:1.5em; }
  .rt-rich a { color:var(--accent); }
  .rt-html { min-height:96px; font-family:monospace; font-size:12px; }
  .grid2 { display:grid; grid-template-columns:1fr 1fr; gap:0 14px; }
  button { padding:8px 13px; border:1px solid var(--line); border-radius:6px;
           background:var(--panel); color:var(--ink); cursor:pointer; font:inherit; }
  button:hover { border-color:var(--accent); }
  button.primary { background:var(--accent); color:#10161f; border-color:var(--accent);
                   font-weight:600; }
  button.danger { color:var(--err); }
  .bar { display:flex; gap:8px; flex-wrap:wrap; margin-top:14px; }
  .spacer { flex:1; }
  /* Sticky Save/Delete bar at the top of the idea form — the form is long
     enough that a bottom-anchored Save meant scrolling for every edit. */
  #formbar { position:sticky; top:0; z-index:5; display:flex; gap:8px;
             align-items:center; padding:8px 0 10px; margin:0 0 4px;
             background:var(--bg); border-bottom:1px solid var(--line); }
  #formbar .who { color:var(--mut); font-size:12px; overflow:hidden;
                  white-space:nowrap; text-overflow:ellipsis; }
  /* Pipeline buttons: forward/back one status. A disabled one keeps its label
     (so you can see where the pipeline goes next) and explains itself on hover. */
  #formbar .step { max-width:15em; overflow:hidden; white-space:nowrap;
                   text-overflow:ellipsis; }
  #formbar .step.fwd { border-color:var(--accent); }
  button[disabled] { opacity:0.42; cursor:not-allowed; }
  button[disabled]:hover { border-color:var(--line); }
  /* Publishing state: hidden ideas are dimmed and chipped everywhere. */
  .chip { display:inline-block; padding:1px 7px; border-radius:10px; font-size:11px;
          border:1px solid var(--line); color:var(--mut); }
  .chip.hidden { background:#42323a; color:#f0c4d2; border-color:#6b4550; }
  .chip.epic { background:#2f3a4a; color:#cfe0ff; border-color:#41556e; }
  .chip.merit { background:#1e3a2b; color:#9fe8c0; border-color:#2c6b4e; }
  /* An idea carrying a manual_step someone RAN and it did not pass. */
  .chip.failed { background:#4a2626; color:#f0b8b8; border-color:#7a3a3a; }
  .row.hid .t, .card.hid .ct { opacity:0.62; text-decoration:line-through; }
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

  /* Admin hand-off panel (design_questions / manual_steps) — internal only. */
  .ho-panel { border:1px solid var(--line); border-radius:6px; padding:10px;
    margin-top:12px; }
  .ho-head { font-weight:600; margin-bottom:8px; }
  .ho-item { border:1px solid var(--line); border-radius:5px; padding:6px;
    margin-bottom:6px; }
  .ho-item.ho-open { border-left:3px solid var(--warn); }
  .ho-item.ho-done { opacity:0.72; }
  .ho-row { display:flex; gap:6px; align-items:flex-start; }
  .ho-row textarea { flex:1; }
  /* Two selects now share the row (status + kind), so neither may stretch. */
  .ho-row select { flex:0 0 auto; width:auto; }
  .ho-row .ho-flag { margin-left:auto; }
  .ho-sr { margin-top:4px; font-size:12px; }
  .ho-del { flex:0 0 auto; line-height:1; padding:4px 8px; }
  .ho-badge { display:inline-block; padding:0 6px; border-radius:999px;
    border:1px solid var(--line); font-size:11px; font-weight:600; }
  .ho-badge.bad { background:#4a2626; color:#f0b8b8; border-color:#7a3a3a; }
  .ho-gate { color:var(--warn); margin-top:6px; }
  /* An unfinished blocker step holds the item back, like an open question. */
  .ho-item.ho-block { border-left:3px solid var(--err); }
  /* Ran and failed: still open, but it needs another code change, not a retry. */
  .ho-item.ho-fail { border-left:3px solid var(--err); }
  .ho-flag { display:flex; align-items:center; gap:4px; font-size:12px;
    color:var(--mut); white-space:nowrap; }
  .ho-flag input { width:auto; margin:0; }
  .ho-item textarea { resize:vertical; }
  /* The tester lane on a UAT step: who holds it, and what they found. */
  .ho-uatbar { display:flex; gap:6px; align-items:center; margin-top:5px;
    flex-wrap:wrap; }
  .ho-uatbar select { flex:0 0 auto; width:auto; font-size:12px; }
  .ho-chip { display:inline-block; padding:1px 7px; border-radius:999px;
    border:1px solid var(--line); font-size:11px; color:var(--mut); }
  .ho-chip.me { border-color:var(--accent); color:var(--fg); }
  .ho-sres { margin-top:4px; font-size:12px; min-height:44px; }
  .ho-ctext { white-space:pre-wrap; font-size:12px; margin-top:3px; }
  .small.bad { color:var(--err); }
  /* A role with no `edit` browses the whole backlog but owns nothing on it, so
     the form reads as a document. Only .tester-ok controls (the three `uat`
     writes) stay live -- select() disables the rest outright, this is just the
     visual half. The server enforces all of it independently. */
  body.readonly #form input, body.readonly #form select,
  body.readonly #form textarea { opacity:0.78; }
  body.readonly #form .rt-tools { display:none; }
  .filters { display:grid; grid-template-columns:1fr 1fr; gap:6px; margin-top:8px; }
  .filters select { padding:5px 7px; font-size:12px; }
  .filters .full { grid-column:1 / -1; }
  .chk { display:flex; align-items:center; gap:6px; margin-top:8px; font-size:12px;
         color:var(--mut); cursor:pointer; }
  .chk input { width:auto; }
  .linkbtn { background:none; border:none; color:var(--accent); cursor:pointer;
             padding:0; font:inherit; font-size:12px; }
  /* Signed-in identity strip, under the menu bar. */
  #whobar { border-top:1px solid var(--line); padding-top:8px; margin-top:2px; }
  #who { color:var(--mut); font-size:12px; }
  #who::before { content:'●'; color:var(--ok); margin-right:5px; font-size:9px;
                 vertical-align:middle; }
  .modal-bg { position:fixed; inset:0; background:rgba(0,0,0,0.55); display:none;
              align-items:flex-start; justify-content:center; padding:6vh 16px; z-index:9; }
  .modal-bg.show { display:flex; }
  .modal { background:var(--panel); border:1px solid var(--line); border-radius:8px;
           width:min(560px,100%); max-height:86vh; overflow:auto; padding:16px 18px; }
  .modal h2 { margin:0 0 10px; }
  /* Scrolling pick-one list (merit player picker). */
  .picklist { border:1px solid var(--line); border-radius:6px; margin:8px 0;
              max-height:46vh; overflow:auto; }
  .pick-off { opacity:.45; cursor:default; }
  .pick { display:flex; gap:10px; align-items:baseline; padding:6px 9px;
          border-bottom:1px solid var(--line); cursor:pointer; }
  .pick:last-child { border-bottom:none; }
  .pick:hover { background:var(--bg); }
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
  .txns.audit td { vertical-align:top; }
  .txns.audit td.nw { white-space:nowrap; }
  .txns.audit td.det { word-break:break-word; }
  .txns.audit tr.bad td { color:var(--err); }
  .txns.audit tr.bad td.muted { color:var(--err); opacity:0.75; }
  /* Detail-column chips: one per idea this write actually changed. */
  .txns.audit td.det .idchip { margin:0 6px 2px 0; }
  .txns.audit td.det .idchip.open { text-decoration:underline; }
  .txns.audit td.det .idchip .n { color:var(--mut); font-size:11px; }
  /* The expander row a chip opens, in place under its own audit row -- there
     is only one modal, so a sub-panel would destroy the table behind it. */
  tr.au-diff > td { background:var(--bg2); padding:6px 10px 10px; }
  table.au-fields { width:100%; border-collapse:collapse; font-size:12px; }
  table.au-fields th { text-align:left; color:var(--mut); font-weight:600;
                       padding:2px 6px; }
  table.au-fields td { vertical-align:top; padding:2px 6px;
                       border-bottom:1px solid var(--line); word-break:break-word; }
  table.au-fields td.f { white-space:nowrap; font-family:ui-monospace,monospace; }
  table.au-fields td.v { width:42%; }
  mark.d-del { background:rgba(220,80,80,0.28); color:inherit; }
  mark.d-add { background:rgba(90,190,120,0.28); color:inherit; }
  #mpending.has { color:var(--warn); font-weight:600; }
  /* header external links */
  .extlinks { display:flex; gap:12px; margin:2px 0 8px; }
  .extlinks a { color:var(--accent); font-size:12px; text-decoration:none; }
  .extlinks a:hover { text-decoration:underline; }
  /* palette finder */
  .pf-bar { display:flex; gap:8px; align-items:center; margin:6px 0; }
  .pf-bar input { flex:1; }
  #pf_results { max-height:52vh; overflow:auto; margin-top:8px; }
  #pf_results table { width:100%; border-collapse:collapse; font-size:12px; }
  #pf_results th, #pf_results td { text-align:left; padding:4px 8px;
    border-bottom:1px solid var(--line); vertical-align:top; }
  #pf_results th { position:sticky; top:0; background:var(--bg2,#161c24);
    color:var(--muted); font-weight:600; }
  #pf_results .pf-path { color:var(--accent); }
  #pf_results .pf-orphan { color:var(--muted); font-style:italic; }
  #pf_results .pf-type { color:var(--muted); text-transform:capitalize; }
  #pf_results .pf-rr { color:var(--muted); font-family:monospace; }
  #pf_results .pf-custom { color:var(--accent); font-weight:600; }
  #pf_results .pf-std { color:var(--muted); }
  .pf-meta { font-size:11px; color:var(--muted); margin-left:auto; }
  /* LLM change review */
  .lc-bar { display:flex; gap:8px; align-items:center; margin:6px 0; flex-wrap:wrap; }
  .lc-group { margin:16px 0 6px; padding:6px 8px; border:1px solid var(--line);
              border-radius:5px; background:var(--bg2,#161c24); }
  .lc-group h3 { margin:0 0 4px; font-size:13px; color:var(--accent); }
  .lc-row { padding:6px 8px; border-bottom:1px solid var(--line); font-size:12px; }
  .lc-row:last-child { border-bottom:none; }
  .lc-file { font-family:monospace; color:var(--muted); }
  .lc-before { color:var(--muted); text-decoration:line-through; }
  .lc-after { color:var(--fg,#dde); }
  .lc-warn { color:#e8a33d; font-size:11px; }
  .lc-risk-hold { border-left:3px solid #d9534f; }
  .lc-risk-review { border-left:3px solid #e8a33d; }
  .lc-risk-auto { border-left:3px solid #4a8f5b; }
  .lc-acts { display:flex; gap:6px; margin-top:4px; }
  .lc-acts button { font-size:11px; padding:2px 8px; }
  .lc-done { opacity:.55; }
  #lc_results { max-height:56vh; overflow:auto; margin-top:8px; }
  /* compare view: one item, its stats, both descriptions */
  .lc-item { margin:14px 0; border:1px solid var(--line); border-radius:5px;
             background:var(--bg2,#161c24); }
  .lc-item > h3 { margin:0; padding:7px 10px; font-size:13px; color:var(--accent);
                  border-bottom:1px solid var(--line); }
  .lc-item h3 .small { color:var(--muted); font-weight:400; }
  .lc-body { display:grid; grid-template-columns:minmax(240px,1fr) 2fr; gap:12px;
             padding:10px; }
  @media (max-width:820px){ .lc-body { grid-template-columns:1fr; } }
  .lc-props { font-size:11px; line-height:1.55; }
  .lc-props li { list-style:none; margin:0 0 2px; }
  .lc-props .rankw { color:var(--accent); }
  .lc-props .rank-top { color:#e8a33d; font-weight:600; }
  .lc-halves { display:flex; flex-direction:column; gap:10px; }
  .lc-half { border-left:3px solid var(--line); padding:2px 0 2px 9px; }
  .lc-half.filled { border-left-color:#4a8f5b; }
  .lc-half .lbl { font-size:10px; text-transform:uppercase; letter-spacing:.06em;
                  color:var(--muted); }
  .lc-half .txt { font-size:12.5px; margin:2px 0 4px; }
  .lc-empty { color:var(--muted); font-style:italic; font-size:12px; }
  .lc-src { font-size:10px; color:var(--muted); }
  .lc-src.sonnet { color:#7aa2f7; }
  .lc-reroll { color:var(--muted); }
  .lc-acts button.rr { border-color:var(--accent); }
  .lc-acts button:disabled { opacity:.5; cursor:progress; }
  /* work queues (Toolset / UAT) — wider than the other modals: these are read
     while you work in another window, so the step text must not be a keyhole. */
  .modal.wide { width:min(1000px,100%); }
  .qgroup { margin:14px 0 4px; font-size:13px; color:var(--accent);
            border-bottom:1px solid var(--line); padding-bottom:3px; }
  .qgroup .n { color:var(--mut); font-weight:400; font-size:11px; margin-left:6px; }
  .qrow { display:flex; gap:10px; padding:7px 4px; border-bottom:1px solid var(--line);
          align-items:flex-start; }
  .qrow.done { opacity:0.45; }
  .qrow.failed { border-left:3px solid var(--err); padding-left:6px; }
  .qfail { color:var(--err); font-size:10px; font-weight:700; letter-spacing:.5px; }
  .qrow .qmeta { flex:0 0 210px; }
  .qrow .qtitle { display:block; color:var(--accent); font-size:12px; cursor:pointer;
                  text-align:left; background:none; border:none; padding:0; width:100%; }
  .qrow .qtitle:hover { text-decoration:underline; }
  .qrow .qsub { color:var(--mut); font-size:11px; }
  .qrow .qtext { flex:1; font-size:12px; white-space:pre-wrap; word-break:break-word; }
  .qrow .qctl { flex:0 0 250px; display:flex; gap:5px; flex-wrap:wrap;
                justify-content:flex-end; }
  .qrow .qctl select, .qrow .qctl input { width:auto; font-size:11px; padding:2px 4px; }
  .qrow .qctl input.tester { flex:1 1 110px; min-width:70px; }
  .qblock { color:var(--warn); font-size:10px; font-weight:700; letter-spacing:.5px; }
  /* The tester lane wraps onto its own lines under the step text. */
  .qrow { flex-wrap:wrap; }
  .qrow .qctl.qclaim { flex:1 1 100%; justify-content:flex-start;
                       align-items:center; }
  .qrow .qresult { flex:1 1 100%; color:var(--mut); border-left:2px solid var(--line);
                   padding-left:8px; margin-left:220px; }
  .qrow .qctl button { width:auto; font-size:11px; padding:2px 8px; }
  .qbar { display:flex; gap:8px; align-items:center; margin:6px 0; }
  .qbar input { flex:1; }
  #qresults { max-height:60vh; overflow:auto; }
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
    <!-- ONE roadmap link, and it points at PRODUCTION. There used to be two -
         this realm's and the live one - because Publish reached this realm's
         wiki only and production waited for the next bin/season-promote.sh.
         Publish now pushes the page into the live season's docs/ as well
         (publish_to_live_realm), so the public roadmap IS the roadmap and a
         second link would only ask "which one is real?".
         There is deliberately NO preview of unpublished work here. A /preview
         route serving docs.manual/Roadmap.html raw was tried and removed: that
         file is a page fragment dressed as a document - no wiki chrome, no
         stylesheet at that path, every cross-page link 404 - so it looked
         broken and told you nothing the editor's own board does not. Publish is
         cheap and reversible; use it.
         The two data-brand hrefs are rewritten by bin/season-brand.py, both
         from SEASON_LIVE_WIKI_URL. The wiki link used to be this realm's own
         (SEASON_WIKI_URL, i.e. dev) - it points at production now for the same
         reason the roadmap link always did: the editor is where you check what
         PLAYERS see, and the dev wiki is a build artefact you can read off
         docs/ locally. -->
    <div class="extlinks">
      <a data-brand="live-wiki" href="https://homerslotr.com/" target="_blank" rel="noopener">Wiki ↗</a>
      <a data-brand="live-roadmap" href="https://homerslotr.com/manual/Roadmap" target="_blank" rel="noopener">Roadmap ↗</a>
      <a id="monitorlink" href="/monitor" target="_blank" rel="noopener">Server monitor ↗</a>
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
      <select id="f_fepic"><option value="">All epics</option></select>
      <select id="f_fhidden">
        <option value="">Published + hidden</option>
        <option value="pub">Published only</option>
        <option value="hid">Hidden only</option>
      </select>
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
      <button id="regen">Save &amp; regenerate HTML</button>
      <button id="publish">Publish to Wiki &amp; DB</button>
    </div>
    <div class="bar">
      <button id="mgroups" class="linkbtn">Manage groups</button>
      <button id="mepics" class="linkbtn">Manage epics</button>
      <button id="mplayers" class="linkbtn">Manage players</button>
      <button id="mpending" class="linkbtn">Pending Merit Requests</button>
      <button id="mpalette" class="linkbtn">Palette Finder</button>
      <button id="mtoolq" class="linkbtn">Toolset Queue</button>
      <button id="muatq" class="linkbtn">UAT Queue</button>
      <button id="muatr" class="linkbtn">UAT Review</button>
      <button id="mchanges" class="linkbtn">LLM Changes</button>
      <button id="maudit" class="linkbtn">Recent changes</button>
      <span class="spacer"></span>
      <span id="count" class="small"></span>
    </div>
    <div class="bar" id="whobar">
      <span id="who" class="small"></span>
      <span class="spacer"></span>
      <button id="logout" class="linkbtn">Sign out</button>
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
let DATA = {ideas:[], vocab:{groups:[],players:[],statuses:[],ids:[]}, me:{caps:[]}};

// ---- Access control -------------------------------------------------------
// The server enforces all of this independently; hiding a control here is so
// nobody is invited to press a button that will refuse them. Never treat CAN()
// as the security boundary.
function CAN(cap){ return ((DATA.me && DATA.me.caps) || []).includes(cap); }
// Statuses only `promote_shipped` may set. Kept in step with
// roadmap_publish.SHIPPED_STATUSES / roadmap_auth.SHIPPED_STATUSES.
const SHIPPED_STATUSES = ['manual','implemented','awarded'];
function canSetStatus(st){ return CAN('promote_shipped') || !SHIPPED_STATUSES.includes(st); }
// No `edit` means the document form is a reader, not an editor. A tester still
// writes — but only through the three narrow `uat` endpoints, never /api/save.
function READONLY(){ return !CAN('edit'); }
// The in-game player name this session credits UAT work to; '' when the account
// is unbound (the server refuses a claim or a result in that case, and says so).
function ME(){ return ((DATA.me && DATA.me.player_name) || '').trim(); }
function isMine(name){
  const me = ME(); return !!me && (name||'').trim().toLowerCase() === me.toLowerCase();
}

// Every call goes through here so an expired session lands on the login page
// instead of surfacing as a bare "NetworkError" from an unhandled 401.
async function api(url, opts){
  const r = await fetch(url, opts);
  if (r.status === 401){ location.href = '/login'; throw new Error('signed out'); }
  return r;
}
let sel = -1;
let baseVersion = null;      // hash of roadmap.yaml as we last loaded/saved it
let baseHashes = null;   // {id: fingerprint} merge baseline from /api/data
let baseVocab = null;    // same, for the groups/players/epics blocks
// Serialized form state as of the last render — the baseline "unsaved changes"
// is measured against. Comparing a snapshot beats listening for input events:
// the rich-text editors fire plenty of events while initialising, and none of
// those are the user changing anything.
let formSnapshot = null;
// The idea object the open form belongs to. `sel` is only an index, and an
// index silently means a *different* idea the moment DATA.ideas is replaced
// (every load()) or reordered — folding the form back in by index then
// overwrites a neighbour, which reads as "an idea disappeared" plus a
// duplicate-id error. Everything that writes the form back resolves this
// reference instead, and refuses to write at all if it can't find it.
let selRef = null;
function curIdx(){
  if (!selRef) return -1;
  return DATA.ideas.indexOf(selRef);
}
let view = 'board';          // 'list' | 'board' — Board is the default view
let showCardDropdown = false; // per-card status <select> on board cards (off by default)
// Board lanes, left→right = pipeline flow. Labels come from DATA.vocab.statuses
// (sourced from gen-roadmap.py STATUS) so they never drift.
const BOARD_LANES = ['planned','later','soon','wip','confirmed','design','manual',
                     'implemented','awarded','unlikely'];
// The pipeline the header-bar forward/back buttons walk. `design` and
// `unlikely` sit off it: from either, forward rejoins the chain (design → back
// to work, unlikely → back under consideration) and back is a dead end.
const CHAIN = ['planned','later','soon','wip','confirmed','manual',
               'implemented','awarded'];
const OFFCHAIN_FWD = {design:'confirmed', unlikely:'planned'};
// Labels that read badly as a button. Everything else uses its STATUS label.
const PIPE_LABEL = {awarded:'Award merit', implemented:'Ship · in testing'};
// Sentinel filter value: match rows whose field is empty/unset.
const BLANK = '__BLANK__';
const BLANK_OPT = `<option value="${BLANK}">&lt;Is Blank&gt;</option>`;
const $ = s => document.querySelector(s);

function statusCls(s){ return s || ''; }
function typeCls(t){ return (t||'').toLowerCase(); }
// Coerce first: not every field arrives as a string. An all-digit commit hash
// (`commit: 45167215955`) comes back from YAML as a *number*, and calling
// .replace on it threw mid-render — the list had already redrawn, so the form
// silently kept showing the previous idea.
function esc(s){ return (s==null?'':String(s)).replace(/[&<>"]/g, c => (
  {'&':'&amp;','<':'&lt;','>':'&gt;','"':'&quot;'}[c])); }

function groupTitle(id){
  const g = DATA.vocab.groups.find(g=>g.id===id);
  return g ? g.title.replace(/&amp;/g,'&') : (id||'—');
}

async function load(){
  const r = await api('/api/data'); DATA = await r.json();
  baseVersion = DATA.version || null;
  // Opaque per-idea fingerprints from the server. We never compute these — we
  // hold them and hand them back on save so the server can tell *which* items
  // we changed and merge around anyone else's edits to other items.
  baseHashes = DATA.base_hashes || null;
  baseVocab = DATA.base_vocab || null;
  populateFilters();
  applyCapabilities();
  if (view==='board'){ const f=$('#form'); if (f) f.style.display='none'; renderBoard(); }
  else { renderList(); if (DATA.ideas.length) select(0); }
  refreshPending();
}

// Update the "X Pending Merit Requests" button label from the live game DB.
function refreshPending(){
  const btn=$('#mpending'); if(!btn) return;
  // The merit views are gated on `merit_view` -- a `tester` is refused, and
  // firing the request anyway would only file a denied.route row per page load.
  if (!CAN('merit_view')) return;
  api('/api/pending').then(r=>r.json()).then(d=>{
    const n=d.count||0;
    btn.textContent=`${n} Pending Merit Request${n===1?'':'s'}`;
    btn.classList.toggle('has', n>0);
  }).catch(()=>{});
}

function epicTitle(id){
  const e=(DATA.vocab.epics||[]).find(e=>e.id===id);
  return e ? (e.title||e.id) : (id||'');
}

// Show who is signed in, and take away the chrome this role cannot use. This
// is presentation only: every one of these actions is refused server-side too,
// so a hidden button is a courtesy, never the control.
function applyCapabilities(){
  const me = DATA.me || {};
  const who = $('#who');
  if (who) who.textContent = me.display_name
    ? `${me.display_name} · ${me.role_label || me.role}` : '';
  // [button id, capability it needs]
  [['mpalette','palette'], ['mchanges','llm_review'],
   ['mpending','merit_view'], ['mplayers','merit_view'],
   ['maudit','audit_view'],
   ['mgroups','edit'], ['mepics','edit'], ['mtoolq','edit'],
   ['add','submit'], ['muatr','merit'],
   ['regen','publish'], ['publish','publish']].forEach(([id, cap])=>{
    const el = $('#'+id);
    if (el) el.style.display = CAN(cap) ? '' : 'none';
  });
  // The Monitor page is a separate document, linked from the header.
  const mon = $('#monitorlink');
  if (mon) mon.style.display = CAN('serverlog') ? '' : 'none';
  // A role with no `edit` (today: `tester`) browses the whole backlog but owns
  // nothing on it. The class drives the CSS that greys the form out; every
  // individual control ALSO checks CAN() before it fires, and the server
  // enforces all of it independently — this is a courtesy, not the control.
  document.body.classList.toggle('readonly', READONLY());
  const cd = $('#f_carddd'); if (cd && READONLY()){ cd.checked = false;
    const w = cd.closest('label'); if (w) w.style.display = 'none'; }
}

function populateFilters(){
  const sSel=$('#f_fstatus'), tSel=$('#f_ftype'), pSel=$('#f_fplayer'), gSel=$('#f_fgroup');
  const eSel=$('#f_fepic');
  const sCur=sSel.value, tCur=tSel.value, pCur=pSel.value, gCur=gSel.value, eCur=eSel.value;
  eSel.innerHTML='<option value="">All epics</option>'+BLANK_OPT+
    (DATA.vocab.epics||[]).map(e=>`<option value="${esc(e.id)}">${esc(e.title||e.id)}</option>`).join('');
  eSel.value=eCur;
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
  const fe=$('#f_fepic').value, fh=$('#f_fhidden').value;
  // Board always shows the awarded lane; the "Show awarded" checkbox only
  // governs the list view.
  const showAwarded=(view==='board') || $('#f_showawarded').checked, sort=$('#f_sort').value;
  let rows = DATA.ideas.map((it,idx)=>({it,idx})).filter(({it})=>{
    if (!showAwarded && it.status==='awarded') return false;
    if (fs && it.status!==fs) return false;
    if (ft){ if (ft===BLANK){ if (it.type) return false; } else if ((it.type||'')!==ft) return false; }
    if (fp){ if (fp===BLANK){ if (it.player) return false; } else if ((it.player||'')!==fp) return false; }
    if (fg && it.group!==fg) return false;
    if (fe){ if (fe===BLANK){ if (it.epic) return false; } else if ((it.epic||'')!==fe) return false; }
    if (fh==='pub' && it.hidden) return false;
    if (fh==='hid' && !it.hidden) return false;
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

// Publishing-state chips shown on list rows and board cards.
function hasFailedStep(it){
  return (it.manual_steps||[]).some(s=>s && typeof s==='object' && s.status==='failed');
}

function chips(it){
  let out='';
  if (it.hidden) out+='<span class="chip hidden">hidden</span> ';
  if (it.epic) out+=`<span class="chip epic">${esc(epicTitle(it.epic))}</span> `;
  // Flag only — a failed step never rewrites the idea's status; moving it back
  // to `manual` stays the admin's call.
  if (hasFailedStep(it)) out+='<span class="chip failed">failed</span> ';
  return out;
}

function renderList(){
  const rows = visibleRows();
  const box=$('#list'); box.innerHTML='';
  rows.forEach(({it,idx})=>{
    const d=document.createElement('div');
    d.className='row'+(idx===sel?' sel':'')+(it.hidden?' hid':'');
    const tbadge = it.type
      ? `<span class="tbadge ${typeCls(it.type)}">${esc(it.type)}</span> ` : '';
    d.innerHTML=`<span class="t">${esc(it.title||'(untitled)')}</span>
      <span class="meta">${tbadge}<span class="badge ${statusCls(it.status)}">${esc(it.status||'?')}</span>
      ${chips(it)}${esc(groupTitle(it.group))}${it.player?' · '+esc(it.player):''}</span>`;
    d.onclick=()=>guard(()=>selectById(it.id, idx));
    box.appendChild(d);
  });
  $('#count').textContent=`${rows.length}/${DATA.ideas.length} ideas`;
}

// Re-render whichever view is active (filters/search call this).
function render(){ if (view==='board') renderBoard(); else renderList(); }

function setView(v){
  // Leaving list view hides the form without re-rendering it, so ask about
  // unsaved edits here — once we are on the board there is no live form and
  // isDirty() can no longer see them.
  if (v==='board' && view==='list' && isDirty()) return guard(()=>setView(v));
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
    const i = curIdx();
    if (i>=0) select(i);
    else if (sel>=0 && DATA.ideas[sel]) select(sel);
    else if (DATA.ideas.length) select(0);
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
        ? `<select class="cst" data-idx="${idx}" data-cur="${esc(it.status)}">${BOARD_LANES.map(ls=>
            `<option value="${esc(ls)}"${ls===it.status?' selected':''}>${esc(statusLabel(ls))}</option>`).join('')}</select>`
        : '';
      return `<div class="card${it.hidden?' hid':''}" draggable="true" data-idx="${idx}">
        <span class="ct">${esc(it.title||'(untitled)')}</span>
        <span class="cmeta">${tbadge}${chips(it)}${esc(groupTitle(it.group))}${it.player?' · '+esc(it.player):''}</span>
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
    if (!CAN('promote_shipped'))
      [...sel0.options].forEach(o=>{
        if (!canSetStatus(o.value) && o.value!==sel0.dataset.cur) o.remove(); });
    sel0.onclick=e=>e.stopPropagation();
    sel0.onchange=e=>moveToStatus(+sel0.dataset.idx, e.target.value);
  });
  // Lane drop targets.
  board.querySelectorAll('.lane').forEach(lane=>{
    lane.ondragover=e=>{ e.preventDefault();
      const ok = canSetStatus(lane.dataset.status);
      e.dataTransfer.dropEffect = ok ? 'move' : 'none';
      if (ok) lane.classList.add('drop'); };
    lane.ondragleave=()=>lane.classList.remove('drop');
    lane.ondrop=e=>{ e.preventDefault(); lane.classList.remove('drop');
      if (dragIdx>=0) moveToStatus(dragIdx, lane.dataset.status); };
  });
}

// Change one idea's status (drag drop or dropdown) and persist via Save.
function moveToStatus(idx, status){
  const it=DATA.ideas[idx];
  if (!it || it.status===status) return;
  // Refuse here rather than let the save come back 403 — by then the card has
  // already moved on screen and has to be put back.
  if (!canSetStatus(status) || !canSetStatus(it.status)){
    banner('bad', 'Only an administrator can move an item '
      + (canSetStatus(it.status) ? 'to' : 'out of') + ' “'
      + statusLabel(canSetStatus(it.status) ? status : it.status) + '”. '
      + 'Everything up to “In progress” is yours, and this item\'s steps and '
      + 'notes stay editable either way.');
    renderBoard();
    return;
  }
  if (status==='awarded' && !CAN('merit')){
    banner('bad', 'Only an administrator can award merit.');
    renderBoard();
    return;
  }
  it.status=status;
  renderBoard();
  commit('/api/save');
}

function opt(value,label,cur){
  return `<option value="${esc(value)}"${value===cur?' selected':''}>${esc(label)}</option>`;
}

// ---- pipeline transitions (header-bar forward/back buttons) --------------
// JS mirror of open_blockers() in the Python half — a blocking manual step that
// isn't done. Legacy bare-string steps were written before the flag existed.
function openBlockers(it){
  return (it.manual_steps||[]).filter(s=>s && typeof s==='object'
    && s.blocker && s.status!=='done');
}
function openQuestions(it){
  return (it.design_questions||[]).filter(q=>q && q.status==='open');
}
function pipeLabel(st){ return PIPE_LABEL[st] || statusLabel(st); }

// What the two pipeline buttons do for this idea. A non-empty `reason` means
// the move isn't legal right now: the button stays visible (so the pipeline is
// still readable) but greyed, with the reason on hover.
function transitions(it){
  const cur = it.status || '';
  const i = CHAIN.indexOf(cur);
  const back = (i > 0) ? CHAIN[i-1] : null;
  const fwd  = (i >= 0) ? (CHAIN[i+1] || null) : (OFFCHAIN_FWD[cur] || null);
  const out = {back:{status:back, label:back?('◀ '+pipeLabel(back)):'', reason:''},
               fwd:{status:fwd, label:fwd?(pipeLabel(fwd)+' ▶'):'', reason:''}};
  if (!back) out.back.reason = (i===0) ? 'Already at the start of the pipeline'
                                       : 'Off the main pipeline — use the Status dropdown';
  if (!fwd)  out.fwd.reason  = (cur==='awarded') ? 'Already the final state'
                                                 : 'No forward step from this status';
  if (!(it.id||'').trim()){
    out.back.reason = out.fwd.reason = 'Give the idea an id and Save it first';
    return out;
  }
  // Shipping gates, same rules the server refuses to save past.
  if (fwd==='implemented' || fwd==='awarded'){
    const n = openBlockers(it).length;
    if (n) out.fwd.reason = n+' unfinished blocker manual step'+(n>1?'s':'');
  }
  if (cur==='design'){
    const n = openQuestions(it).length;
    if (n) out.fwd.reason = n+' open design question'+(n>1?'s':'');
  }
  if (fwd==='awarded'){
    if (!it.type) out.fwd.reason = 'Set a type (Defect/Enhancement/Exploit) — '
                                 + 'it decides how much merit is granted';
    // Already paid: the move is legal, it just must not pay again.
    else if (it.merit_awarded) out.fwd.label = 'Mark awarded ▶';
  }
  // Role gates, last so they override a merely-informational reason. Shown as a
  // disabled button with an explanation rather than a hidden one: "why can't I
  // ship this?" deserves an answer in place. The server enforces the same rules.
  if (fwd && !canSetStatus(fwd))
    out.fwd.reason = 'Only an administrator can move an item to “'
                   + statusLabel(fwd) + '”';
  if (back && !canSetStatus(cur))
    out.back.reason = 'Only an administrator can move an item out of “'
                    + statusLabel(cur) + '”';
  if (fwd==='awarded' && !CAN('merit'))
    out.fwd.reason = 'Only an administrator can award merit';
  return out;
}

// The idea as the form currently has it, not as the file has it — the pipeline
// buttons must judge the edits you can see (a status just picked, a blocker
// step just ticked done), not the last saved copy.
function liveIdea(){
  const it = DATA.ideas[curIdx()] || {};
  if (!$('#f_id')) return it;
  const ho = HO ? handoffOut() : {};
  return Object.assign({}, it, {
    id: $('#f_id').value.trim(), status: $('#f_status').value,
    type: $('#f_type').value, player: $('#f_player').value.trim(),
    manual_steps: ho.manual_steps || [],
    design_questions: ho.design_questions || []});
}

function formbarHTML(it){
  const tr = transitions(it);
  const stepBtn = (id, t, cls) => t.status
    ? `<button id="${id}" class="step ${cls}"${t.reason?' disabled':''}
         title="${esc(t.reason || ('Move to: '+statusLabel(t.status)))}"
         >${esc(t.label)}</button>`
    : `<button id="${id}" class="step ${cls}" disabled
         title="${esc(t.reason)}">${cls==='fwd'?'▶':'◀'}</button>`;
  return `
      <button class="primary" id="save">Save</button>
      <button class="danger" id="del">Delete</button>
      <span class="spacer"></span>
      ${it.merit_awarded ? '<span class="chip merit">merit paid</span>'
        + (CAN('merit')
           ? '<button class="danger" id="revoke">Revoke merit points</button>' : '') : ''}
      ${stepBtn('t_back', tr.back, 'back')}
      ${stepBtn('t_fwd', tr.fwd, 'fwd')}`;
}

// (Re)wire the bar. Called on every render and whenever a field the buttons
// depend on changes, so a status/type/blocker edit re-labels them immediately.
function bindFormbar(){
  const tr = transitions(liveIdea());
  $('#save').onclick = ()=>commit('/api/save');
  $('#del').onclick = del;
  const bb=$('#t_back'), fb=$('#t_fwd'), rb=$('#revoke');
  if (bb && !bb.disabled) bb.onclick = ()=>stepTo(tr.back.status);
  if (fb && !fb.disabled) fb.onclick = ()=>stepTo(tr.fwd.status);
  if (rb) rb.onclick = revokeMerit;
}

function refreshFormbar(){
  const bar = $('#formbar'); if (!bar) return;
  bar.innerHTML = formbarHTML(liveIdea());
  bindFormbar();
}

// ---- id autofill from the title -----------------------------------------
// An id is a stable key: `dupe_of` points at it, the in-page merge fingerprints
// by it, and `#idea-<id>` anchors are linked from other notes. So this only ever
// FILLS AN EMPTY id — it never rewrites one that already exists, no matter how
// the title later changes.

function slugifyId(title){
  return (title||'')
    .normalize('NFD').replace(/[\u0300-\u036f]/g, '')  // "Théoden" -> "Theoden"
    .toLowerCase()
    .replace(/['\u2019]/g, '')            // don't let "boss's" become "boss-s"
    .replace(/[^a-z0-9]+/g, '-')          // everything else becomes a separator
    .replace(/^-+|-+$/g, '');
}

// Trim to a sane length on a word boundary — ids show up in URLs, dupe_of
// pickers and conflict messages, and a 200-char one is unusable there.
function shortenId(slug, max){
  if (slug.length <= max) return slug;
  const cut = slug.slice(0, max);
  const at = cut.lastIndexOf('-');
  return (at > max/2 ? cut.slice(0, at) : cut).replace(/-+$/, '');
}

// Append -2, -3, … until nothing else in the file uses it. `skipIdx` is the row
// being edited, so an id never collides with itself.
function uniqueIdeaId(base, skipIdx){
  // Case-insensitive: the file still carries a few mixed-case ids (e.g.
  // `Commoner-troll-faction`), and minting a lowercase twin of one would give
  // two ids that differ only in case — ambiguous in dupe_of and as an anchor.
  const taken = new Set(DATA.ideas
    .map((x,j)=> j===skipIdx ? null : (x.id||'').toLowerCase())
    .filter(Boolean));
  if (!taken.has(base)) return base;
  for (let n=2; ; n++){
    const cand = base + '-' + n;
    if (!taken.has(cand)) return cand;
  }
}

function autofillIdFromTitle(){
  const idEl = $('#f_id'), titleEl = $('#f_title');
  if (!idEl || !titleEl) return;
  if (idEl.value.trim()) return;          // never overwrite an existing id
  const slug = shortenId(slugifyId(titleEl.value), 60);
  if (!slug) return;                      // title was punctuation only
  idEl.value = uniqueIdeaId(slug, curIdx());
}

function select(i){
  sel = i; formSnapshot = null; selRef = DATA.ideas[i] || null; renderList();
  const it = DATA.ideas[i]; if (!it) { $('#form').innerHTML=''; return; }
  const groups = DATA.vocab.groups.map(g=>opt(g.id, g.title.replace(/&amp;/g,'&'), it.group)).join('');
  // Statuses this account may not set are dropped from the picker -- except
  // the item's OWN current status, which has to stay in the list or selecting a
  // shipped item would silently show (and then save) the wrong status.
  const stats  = DATA.vocab.statuses
      .filter(s=>canSetStatus(s.id) || s.id===it.status)
      .map(s=>opt(s.id, s.id+' — '+s.label, it.status)).join('');
  const types  = ['<option value=""></option>'].concat(
      (DATA.vocab.types||[]).map(t=>opt(t.id, t.label, it.type||''))).join('');
  const players = ['<option value=""></option>'].concat(
      DATA.vocab.players.map(p=>opt(p,p,it.player||''))).join('');
  const dupes = ['<option value=""></option>'].concat(
      DATA.vocab.ids.filter(id=>id!==it.id).map(id=>opt(id,id,it.dupe_of||''))).join('');
  const epics = ['<option value="">(none)</option>'].concat(
      (DATA.vocab.epics||[]).map(e=>opt(e.id, e.title||e.id, it.epic||''))).join('');
  $('#form').innerHTML = `
    <div id="formbar">${formbarHTML(it)}</div>
    <label>Title (this IS the public one-line description)</label>
    <input id="f_title" value="${esc(it.title)}">
    <div class="grid2">
      <div><label>Group</label><select id="f_group">${groups}</select></div>
      <div><label>Status</label><select id="f_status">${stats}</select></div>
    </div>
    <div class="grid2">
      <div><label>Type (Defect / Enhancement / Exploit)</label>
        <select id="f_type">${types}</select></div>
      <div><label>Epic (rolls this item up under one published card)</label>
        <select id="f_epic">${epics}</select></div>
    </div>
    <label class="chk"><input type="checkbox" id="f_hidden"${it.hidden?' checked':''}>
      Hidden &mdash; never publish to the wiki roadmap or the in-game Recent Updates board</label>
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
    <label>Notes <span class="small">&mdash; player-facing release note, shown on
      the public roadmap. Keep it high level; link to a manual page for detail.</span></label>
    ${rtWidget('notes')}
    <div id="handoff"></div>
    <div class="ho-panel">
      <label>Implementation notes <span class="small">(internal &mdash; never shown
        on the public roadmap). Resrefs, scripts, DB tables, why.</span></label>
      ${rtWidget('impl')}
    </div>
    <p class="small">Order in this list = order in the file. Use the buttons to move.</p>
    <div class="bar">
      <button id="up">↑ Move up</button>
      <button id="down">↓ Move down</button>
    </div>
    <div id="merit"></div>
    <div id="merit_ingame"></div>`;
  bindPlayerHint();
  initEditor('notes', it.notes, it.notes_h, NOTES_DEFAULT_H);
  initHandoff(it);
  initEditor('impl', it.impl_notes, it.impl_notes_h, IMPL_DEFAULT_H);
  renderMerit(it.player||'');
  renderMeritIngame(it.player||'');
  $('#f_player').addEventListener('input', e=>{
    const v=e.target.value.trim();
    renderMerit(v); renderMeritIngame(v);
  });
  // Fill the id when the admin tabs/clicks out of an empty-id new idea.
  $('#f_title').addEventListener('blur', autofillIdFromTitle);
  $('#up').onclick = ()=>move(-1);
  $('#down').onclick = ()=>move(1);
  bindFormbar();
  // Status/type/blocker edits change what the pipeline buttons may do. `change`
  // (not `input`) so the rich-text editors don't rebuild the bar per keystroke.
  $('#form').onchange = refreshFormbar;   // property, not addEventListener:
                                          // select() re-renders often and these
                                          // would otherwise stack up.
  // Baseline for the unsaved-changes guard: whatever the form says right now.
  formSnapshot = snapshot();
  lockFormIfReadOnly();
}

// A role with no `edit` (today: `tester`) reads the whole form and writes
// nothing through it. Done here, after every render, rather than by threading a
// flag through the markup: the panel re-renders on its own (renderHandoff) and
// a per-widget `disabled` attribute would have to be repeated in a dozen
// template strings and would be forgotten in the thirteenth.
//
// `.tester-ok` opts a control back in -- those are the three `uat` writes, which
// do not go through /api/save at all. The server refuses everything else on its
// own; this only stops the page inviting a click that would be denied.
function lockFormIfReadOnly(){
  if (!READONLY()) return;
  const f = $('#form'); if (!f) return;
  f.querySelectorAll('input, select, textarea, button').forEach(el=>{
    if (el.closest('.tester-ok') || el.classList.contains('tester-ok')) return;
    el.disabled = true;
  });
  // The rich-text editors are contenteditable, which `disabled` does not reach.
  f.querySelectorAll('[contenteditable]').forEach(el=>
    el.setAttribute('contenteditable', 'false'));
}

// ---- pipeline moves ------------------------------------------------------
// Every move folds the open form in and saves, so an edit made just before
// clicking a pipeline button is never lost. Only the move into `awarded` goes
// through /api/award — the one path that touches the live merit database.
function stepTo(status){
  if (status !== 'awarded'){
    $('#f_status').value = status;
    return commit('/api/save', false, {stay:true});
  }
  return awardFlow();
}

function doAward(it, prev, cdkey, skip){
  $('#f_status').value = 'awarded';
  return commit('/api/award', false, {stay:true, extra:{
    idea_id: it.id, prev_status: prev, cdkey: cdkey||'', skip_merit: !!skip}});
}

async function awardFlow(){
  const it = DATA.ideas[curIdx()]; if (!it) return;
  const prev = it.status;
  const name = $('#f_player').value.trim();
  const type = $('#f_type').value;
  const pts = MERIT_POINTS[type] || 0;
  // Already paid once — move the status, never grant twice.
  if (it.merit_awarded) return doAward(it, prev, '', true);
  if (!name || name === 'community'){
    if (!confirm('This idea has no individual submitter'
      + (name ? ' (credited to "community")' : '')
      + ', so no merit can be granted.\n\nMove it to "Merit awarded" anyway? '
      + 'The status changes and nothing is written to the merit database.')) return;
    return doAward(it, prev, '', true);
  }
  // Resolve the submitter first: an unmatched name gets a picker rather than a
  // failed award (roadmap names and in-game login names drift apart).
  let m = {};
  try { m = await (await api('/api/merit?player='+encodeURIComponent(name))).json(); }
  catch(e){ m = {}; }
  if (m.available && m.matched === false) return pickMeritPlayer(it, prev, name, type, pts);
  const who = m.matched_name || name;
  if (!confirm('Grant '+pts+' merit point'+(pts>1?'s':'')+' ('+type+') to '+who
    + ' in the live merit database?\n\nThe game DB is written now; the status '
    + 'only moves if that write succeeds.')) return;
  return doAward(it, prev, '', false);
}

// The roadmap player name matched nothing in meritdb. Show every known player
// and let the admin say who it is; the choice is remembered server-side so the
// same roadmap name resolves by itself next time.
async function pickMeritPlayer(it, prev, name, type, pts){
  let res = {};
  try { res = await (await api('/api/meritplayers')).json(); } catch(e){ res={}; }
  const rows = res.rows || [];
  if (!rows.length){
    banner('bad', 'No merit database players to choose from'
      + (res.reason ? ' — '+res.reason : '') + '.');
    return;
  }
  modalHTML(`<h2>Who is “${esc(name)}”?</h2>
    <p class="small">No merit-database player matched this roadmap name. Pick the
      account to credit with ${pts} point${pts>1?'s':''} (${esc(type)}). The match
      is remembered for next time.</p>
    <input id="mp_q" placeholder="Filter by name…" style="width:100%">
    <div id="mp_list" class="picklist"></div>
    <div class="bar"><span class="spacer"></span><button id="mp_close">Cancel</button></div>`);
  const draw = ()=>{
    const q = ($('#mp_q').value||'').toLowerCase();
    const hits = rows.filter(r=>!q || (r.name||'').toLowerCase().includes(q));
    $('#mp_list').innerHTML = hits.slice(0,200).map((r,i)=>
      `<div class="pick" data-i="${rows.indexOf(r)}"><b>${esc(r.name||'(no name)')}</b>
        <span class="small">balance ${r.balance} · last login ${esc(r.last_login||'—')}</span></div>`
    ).join('') || '<p class="small">No match.</p>';
    $('#mp_list').querySelectorAll('.pick').forEach(d=>{
      d.onclick = ()=>{
        const r = rows[+d.dataset.i];
        if (!confirm('Grant '+pts+' merit point'+(pts>1?'s':'')+' ('+type+') to '
          + r.name + '?\n\n"' + name + '" will be remembered as this account.')) return;
        closeModal();
        doAward(it, prev, r.cdkey, false);
      };
    });
  };
  $('#mp_q').oninput = draw; draw(); $('#mp_q').focus();
  $('#mp_close').onclick = closeModal;
}

function revokeMerit(){
  const it = DATA.ideas[curIdx()]; if (!it || !it.merit_awarded) return;
  const pts = MERIT_POINTS[it.type] || 0;
  if (!confirm('Take back '+pts+' merit point'+(pts>1?'s':'')+' from '
    + (it.player||'this submitter') + '?\n\nThis subtracts from the live merit '
    + 'database and writes a negative ledger entry. The idea keeps its status; '
    + 'only the "merit paid" flag is cleared.')) return;
  return commit('/api/revoke', false, {stay:true, extra:{idea_id: it.id}});
}

// Lifetime merit for a submitter: count their *awarded* (totally done) ideas by
// type and weight them Defect=1, Enhancement=2, Exploit=3.
const MERIT_POINTS = {Defect:1, Enhancement:2, Exploit:3, UAT:1};
function playerMerit(name){
  const c={Defect:0, Enhancement:0, Exploit:0}; let untyped=0, uat=0;
  const lc=(name||'').toLowerCase();
  DATA.ideas.forEach(it=>{
    // UAT credit is independent of who reported the idea and of its status, so
    // it is counted across EVERY idea, not just this player's awarded ones.
    (it.uat_credits||[]).forEach(u=>{
      if(u && u.awarded && (u.player||'').toLowerCase()===lc) uat++;
    });
    if(it.status!=='awarded' || (it.player||'')!==name) return;
    if(c[it.type]!=null) c[it.type]++; else untyped++;
  });
  const total=c.Defect*MERIT_POINTS.Defect + c.Enhancement*MERIT_POINTS.Enhancement
            + c.Exploit*MERIT_POINTS.Exploit + uat*MERIT_POINTS.UAT;
  return {c, untyped, uat, total};
}

function renderMerit(name){
  const box=$('#merit'); if(!box) return;
  if(!name){ box.innerHTML=''; return; }
  const {c, untyped, uat, total}=playerMerit(name);
  const awarded=c.Defect+c.Enhancement+c.Exploit;
  const chip=(t,n)=>`<span class="tbadge ${t.toLowerCase()}">${t}: ${n}</span>`;
  const note = untyped>0
    ? `<div class="note">${untyped} awarded item(s) for this player have no type set — not counted.</div>` : '';
  box.innerHTML=`<div class="merit">
    <h3>Lifetime merit — <span class="who">${esc(name)}</span></h3>
    <div class="counts">${chip('Defect',c.Defect)} ${chip('Enhancement',c.Enhancement)} ${chip('Exploit',c.Exploit)}
      ${uat?`<span class="tbadge uat">UAT: ${uat}</span>`:''}</div>
    <div class="pts">Total awarded points: <b>${total}</b></div>
    <div class="sub">${awarded} awarded idea(s)${uat?` · ${uat} fix${uat>1?'es':''} validated`:''}
      · Defect=1, Enhancement=2, Exploit=3, UAT=1.</div>
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
  // Same reason as refreshPending(): /api/merit needs `merit_view`.
  if(!name || !CAN('merit_view')){ box.innerHTML=''; return; }
  const my = ++meritReq;
  box.innerHTML=`<div class="merit"><div class="sub">Loading in-game merit…</div></div>`;
  api('/api/merit?player='+encodeURIComponent(name))
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
        <div class="counts">${chip('Defect',d.bugs)} ${chip('Enhancement',d.features)} ${chip('Exploit',d.exploits)}
          ${d.uat?`<span class="tbadge uat">UAT: ${d.uat}</span>`:''}</div>
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

// ---- rich-text editor widget ---------------------------------------------
// One factory, instantiated per field ('notes' = player-facing release note,
// 'impl' = internal implementation notes). Each instance owns its own tabs,
// toolbar, contenteditable pane and HTML-source textarea, all id-prefixed.
const NOTES_DEFAULT_H = 128;       // px; double the old textarea min-height
const IMPL_DEFAULT_H = 96;
let savedRange = null;             // selection saved before opening the link picker
let RT = {};                       // prefix -> editor instance
let rtActive = null;               // editor a modal (link picker) is inserting into

// Markup for one editor; ids are `<prefix>_tab_rich`, `<prefix>_rich`, etc.
function rtWidget(p){
  return `<div class="tabs">
      <button type="button" class="tab active" id="${p}_tab_rich">Rich text</button>
      <button type="button" class="tab" id="${p}_tab_html">HTML</button>
    </div>
    <div class="rt-wrap">
      <div class="rt-tools" id="${p}_tools">
        <button type="button" data-cmd="bold" title="Bold"><b>B</b></button>
        <button type="button" data-cmd="italic" title="Italic"><i>I</i></button>
        <button type="button" data-cmd="underline" title="Underline"><u>U</u></button>
        <span class="sep"></span>
        <button type="button" data-cmd="insertUnorderedList" title="Bullet list">&bull; List</button>
        <button type="button" data-cmd="insertOrderedList" title="Numbered list">1. List</button>
        <span class="sep"></span>
        <input type="color" id="${p}_color" value="#6ea8fe" title="Font color">
        <span class="sep"></span>
        <button type="button" id="${p}_link" title="Link to another idea">&#128279; Idea</button>
        <button type="button" id="${p}_extlink" title="Insert web link">&#128279; URL</button>
        <button type="button" data-cmd="removeFormat" title="Clear formatting">Clear</button>
      </div>
      <div class="rt-rich" id="${p}_rich" contenteditable="true"></div>
      <textarea class="rt-html" id="${p}_html" style="display:none"></textarea>
    </div>`;
}

// Treat an editor that holds no real text and no block/inline content as empty,
// so blank notes don't serialize a stray "<br>" into roadmap.yaml.
function normalizeNotes(html){
  const tmp=document.createElement('div'); tmp.innerHTML=html||'';
  if (tmp.textContent.trim()==='' && !/<(ul|ol|li|img|a|hr|table)/i.test(html||''))
    return '';
  return (html||'').trim();
}

// Build (or rebuild, after the form re-renders) one editor over `value`.
function initEditor(p, value, savedH, defaultH){
  const rich=$('#'+p+'_rich'), html=$('#'+p+'_html');
  const ed = RT[p] = {
    prefix:p, rich, html, tab:'rich', defaultH,
    visible(){ return this.tab==='html' ? this.html : this.rich; },
    value(){ return normalizeNotes(this.tab==='html'
      ? this.html.value : this.rich.innerHTML); },
    height(){ return Math.round(this.visible().offsetHeight); },
  };
  rich.innerHTML = value || '';
  html.value = value || '';
  const h = (savedH && savedH>0) ? savedH : defaultH;
  rich.style.height = h+'px'; html.style.height = h+'px';
  rich.style.display=''; html.style.display='none';
  $('#'+p+'_tab_rich').classList.add('active');
  $('#'+p+'_tab_html').classList.remove('active');

  $('#'+p+'_tab_rich').onclick=()=>switchNotes(ed,'rich');
  $('#'+p+'_tab_html').onclick=()=>switchNotes(ed,'html');
  $('#'+p+'_tools').querySelectorAll('button[data-cmd]').forEach(b=>{
    b.onmousedown=e=>e.preventDefault();            // keep the editor's selection
    b.onclick=()=>{ rich.focus(); document.execCommand(b.dataset.cmd, false, null); };
  });
  const col=$('#'+p+'_color');
  col.onmousedown=()=>{ saveRange(); };
  col.oninput=()=>{ rich.focus(); restoreRange();
    document.execCommand('foreColor', false, col.value); };
  const lb=$('#'+p+'_link');
  lb.onmousedown=e=>{ e.preventDefault(); saveRange(); };
  lb.onclick=()=>{ rtActive=ed; openIdeaLink(); };
  const xb=$('#'+p+'_extlink');
  xb.onmousedown=e=>{ e.preventDefault(); saveRange(); };
  xb.onclick=()=>{ rtActive=ed; openExtLink(); };

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

function switchNotes(ed, to){
  const {rich, html, prefix:p} = ed;
  if (to===ed.tab) return;
  const curH = ed.visible().offsetHeight;
  if (to==='html'){ html.value = rich.innerHTML; }
  else { rich.innerHTML = html.value; }
  ed.tab=to;
  rich.style.display = to==='rich'?'':'none';
  html.style.display = to==='html'?'':'none';
  ed.visible().style.height = curH+'px';            // carry the height across views
  $('#'+p+'_tab_rich').classList.toggle('active', to==='rich');
  $('#'+p+'_tab_html').classList.toggle('active', to==='html');
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
  const ids = DATA.vocab.ids.filter(id=>id!==(DATA.ideas[curIdx()]||{}).id);
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
    insertIntoNotes(link);
  };
  $('#ilink_close').onclick=closeModal;
  const filt=$('#ilink_f');
  filt.oninput=()=>{ const q=filt.value.toLowerCase();
    document.querySelectorAll('#ilink_rows .mrow').forEach(r=>{
      r.style.display = r.textContent.toLowerCase().includes(q)?'':'none'; }); };
  document.querySelectorAll('#ilink_rows .mrow').forEach(r=>
    r.onclick=()=>apply(r.dataset.id));
}

// Insert raw HTML at the saved caret, in the editor whose toolbar opened the
// modal and in whichever of its two tabs is active.
function insertIntoNotes(html){
  const ed = rtActive || RT.notes; if (!ed) return;
  if (ed.tab==='html'){
    const ta=ed.html;
    const a=ta.selectionStart, b=ta.selectionEnd;
    ta.value = ta.value.slice(0,a) + html + ta.value.slice(b);
    ta.focus(); ta.selectionStart=ta.selectionEnd=a+html.length;
  } else {
    ed.rich.focus(); restoreRange();
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

// ---- Admin hand-off panel: design_questions + manual_steps -----------------
// These are the admin's to-do surface (the retired admin-action-required.md).
// They are internal: never rendered on the public board, edited only here.
let HO = {design_questions: [], manual_steps: [], uat_credits: []};

// Must match the textarea `min-height` in the CSS above. A smaller value is
// unreachable — min-height wins over the inline height, so the measured
// offsetHeight would never equal it and syncHandoffHeights() would stamp a
// spurious `*_h` on every sub-item of every idea it saved (this is where the
// `step_h: 64` noise all over roadmap.yaml came from).
const HO_DEFAULT_H = 64;
// One ordered list of step states, shared by the hand-off panel and the two
// queue popups so the dropdowns can never drift apart. Mirrors STEP_STATUS.
const STEP_ORDER = ['open','wip','failed','done'];
const STEP_LABEL = {open:'Open', wip:'In progress', failed:'Failed', done:'Complete'};
// The queues speak in tasks rather than workflow states, hence the second map.
const QSTEP_LABEL = {open:'To do', wip:'In progress', failed:'Failed', done:'Done'};
const isFailed = s => s && s.status==='failed';
// The manual_step keys this panel owns and rewrites. Anything else on a step is
// passed through untouched by handoffOut() — see the note there.
const HO_OWNED = ['step','status','kind','blocker','tester','step_h',
                  'claimed_by','result','tested_by','tested_on'];

// A blocker step that isn't Complete holds the item back, exactly as an open
// design question does. Mirrors open_blockers() in the Python half.
function isOpenBlocker(s){ return !!s.blocker && s.status!=='done'; }

function hpx(v){ return ((v && v>0) ? v : HO_DEFAULT_H) + 'px'; }

function initHandoff(it){
  HO = {
    design_questions: (it.design_questions||[]).map(q=>({
      question: q.question||'', status: q.status||'open', answer: q.answer??null,
      question_h: q.question_h||null, answer_h: q.answer_h||null})),
    // Legacy bare-string steps upgrade to the mapping form on load.
    // Every key normalize_step() can emit must survive the round trip: this
    // panel rewrites the whole manual_steps list on save, so a field it fails
    // to carry is a field it DELETES. `kind` and `tester` were dropped here for
    // months, which silently demoted every uat/toolset/publish step to `admin`
    // and dropped it out of both queues and out of open_uat_steps() — the
    // "shipped but not validated" predicate the wiki and the in-game sign share.
    manual_steps: (it.manual_steps||[]).map(s=>
      (typeof s === 'string')
        ? {step:s, status:'open', kind:'admin', blocker:false, tester:'',
           step_h:null}
        : Object.assign({}, s, {
           step:s.step||'', status:s.status||'open',
           kind: STEP_KINDS.indexOf(s.kind)>=0 ? s.kind : 'admin',
           blocker:!!s.blocker, tester:s.tester||'', step_h:s.step_h||null,
           // The tester's half of the step. `tested_by`/`tested_on` are stamped
           // by /api/uat-result and no input owns them, so they are carried
           // through verbatim exactly as uat_credits' `awarded` is.
           claimed_by:s.claimed_by||'', result:s.result||'',
           tested_by:s.tested_by||'', tested_on:s.tested_on||''})),
    // `awarded`/`date` are server-written (see UAT_FIELD in the Python half) and
    // no input owns them — carried through verbatim so an unrelated edit to this
    // form can never clear a paid credit.
    uat_credits: (it.uat_credits||[]).map(c=>
      (typeof c === 'string')
        ? {player:c, awarded:false, date:''}
        : {player:c.player||'', awarded:!!c.awarded, date:c.date||''}),
    // Read-only in the panel. `comments` is append-only and is deliberately NOT
    // in FORM_FIELDS, so pruneEmpty() copies it through from the loaded idea
    // and only /api/idea-comment ever adds to it.
    comments: (it.comments||[]).map(c=>
      (typeof c === 'string')
        ? {author:'', date:'', text:c}
        : {author:c.author||'', date:c.date||'', text:c.text||''}),
  };
  renderHandoff();
}

// Capture the live textarea heights back into HO before anything that destroys
// the DOM (a re-render) or reads the model (a save) — otherwise a resize is lost.
function syncHandoffHeights(){
  const el = $('#handoff'); if(!el) return;
  const grab = (sel, key) => el.querySelectorAll(sel).forEach(t=>{
    const list = key==='step_h' ? HO.manual_steps : HO.design_questions;
    const item = list[+t.dataset.i]; if(!item) return;
    const h = Math.round(t.offsetHeight);
    item[key] = (h && h!==HO_DEFAULT_H) ? h : null;
  });
  grab('.ho-qt','question_h'); grab('.ho-qa','answer_h'); grab('.ho-st','step_h');
}

// The tester's half of a UAT step: who has it, what they found, and the two
// buttons that are the ONLY writes a role without `edit` can make to a step.
// Both post to their own endpoint rather than going through the form's Save,
// because a tester's /api/save is refused at the route table.
function uatStepBarHTML(s, i){
  const held = (s.claimed_by||'').trim();
  const mine = isMine(held);
  const stamp = (s.tested_by||'').trim()
    ? `<span class="small">reported by ${esc(s.tested_by)}${
         s.tested_on?' · '+esc(s.tested_on):''}</span>` : '';
  let claim = '';
  if (CAN('uat')){
    if (!held) claim = `<button type="button" class="ho-claim tester-ok"
        data-i="${i}" title="Tell everyone you are running this check">Claim</button>`;
    else if (mine || CAN('edit')) claim = `<button type="button"
        class="ho-release tester-ok" data-i="${i}"
        title="Hand it back to the pool">Release</button>`;
  }
  return `
    <div class="ho-uatbar">
      ${held ? `<span class="ho-chip${mine?' me':''}">claimed by ${esc(held)}</span>`
             : '<span class="small">unclaimed</span>'}
      ${claim}
      <span class="spacer"></span>
      ${stamp}
    </div>
    <textarea class="ho-sres tester-ok" data-i="${i}"
              placeholder="What happened when you ran it? (the admin reads this
before paying the merit)">${esc(s.result||'')}</textarea>
    ${CAN('uat') ? `<div class="ho-uatbar">
      <select class="ho-sresst tester-ok" data-i="${i}"
              title="What this run showed">
        <option value="wip"${s.status==='wip'?' selected':''}>Still checking</option>
        <option value="done"${s.status==='done'?' selected':''}>Passed</option>
        <option value="failed"${s.status==='failed'?' selected':''}>Failed</option>
      </select>
      <button type="button" class="ho-submit tester-ok" data-i="${i}"
              title="Send this result to the admin for review">Submit result</button>
      <span class="spacer"></span>
      ${ME() ? '' : '<span class="small bad">your account has no player name — '
                  + 'ask the admin to bind one before reporting</span>'}
    </div>` : ''}`;
}

// Append-only per-idea notes. Rendered for everyone, writable by anyone with
// `uat` (which is every role) -- it is how a tester, who has no `edit`, adds
// information to an item at all. There is no edit or delete: see _comment_write.
function commentsHTML(){
  const rows = (HO.comments||[]).map(c=>`
    <div class="ho-item">
      <div class="ho-row"><b style="flex:1">${esc(c.author||'—')}</b>
        <span class="small">${esc(c.date||'')}</span></div>
      <div class="ho-ctext">${esc(c.text)}</div>
    </div>`).join('');
  return `
    <label style="margin-top:10px">Notes &amp; findings
      ${(HO.comments||[]).length?`<span class="ho-badge">${HO.comments.length}</span>`:''}
      <span class="small">(internal, append-only — once added, a note stays)</span></label>
    ${rows||'<p class="small">None.</p>'}
    ${CAN('uat') ? `<textarea id="ho_ctext" class="tester-ok"
        placeholder="Add a note — repro details, a side effect you spotted, anything
the builder should know"></textarea>
      <button type="button" id="ho_addc" class="tester-ok">+ Add note</button>` : ''}`;
}

function renderHandoff(){
  const el = $('#handoff'); if(!el) return;
  syncHandoffHeights();
  const open = HO.design_questions.filter(q=>q.status==='open').length;
  const blocked = HO.manual_steps.filter(isOpenBlocker).length;
  const todo = HO.manual_steps.filter(s=>s.status!=='done').length;
  const failed = HO.manual_steps.filter(isFailed).length;
  const qs = HO.design_questions.map((q,i)=>`
    <div class="ho-item ${q.status==='open'?'ho-open':'ho-done'}">
      <div class="ho-row">
        <select class="ho-qs" data-i="${i}">
          <option value="open"${q.status==='open'?' selected':''}>Open</option>
          <option value="answered"${q.status==='answered'?' selected':''}>Answered</option>
        </select>
        <button type="button" class="ho-del" data-kind="q" data-i="${i}"
                title="Delete this question">&times;</button>
      </div>
      <textarea class="ho-qt" data-i="${i}" style="height:${hpx(q.question_h)}"
                placeholder="The blocking question">${esc(q.question)}</textarea>
      <textarea class="ho-qa" data-i="${i}" style="height:${hpx(q.answer_h)}"
                placeholder="Your answer (fill in, then set Answered)">${esc(q.answer||'')}</textarea>
    </div>`).join('');
  // Failed first (it needs another code change), then blockers, then anything
  // unfinished, then completed steps.
  const order = HO.manual_steps
    .map((s,i)=>[i,s])
    .sort((a,b)=>(isFailed(b[1])-isFailed(a[1]))
              || (isOpenBlocker(b[1])-isOpenBlocker(a[1]))
              || ((a[1].status==='done')-(b[1].status==='done')));
  const ms = order.map(([i,s])=>`
    <div class="ho-item ${isOpenBlocker(s)?'ho-block'
        :(isFailed(s)?'ho-fail':(s.status==='done'?'ho-done':''))}">
      <div class="ho-row">
        <select class="ho-ss" data-i="${i}">
          ${STEP_ORDER.map(v=>
            `<option value="${v}"${s.status===v?' selected':''}>${STEP_LABEL[v]}</option>`).join('')}
        </select>
        <select class="ho-sk" data-i="${i}"
                title="Which queue this step belongs to">
          ${STEP_KINDS.map(k=>
            `<option value="${k}"${s.kind===k?' selected':''}>${k}</option>`).join('')}
        </select>
        <label class="ho-flag" title="Holds the item back until Complete">
          <input type="checkbox" class="ho-sb" data-i="${i}"${s.blocker?' checked':''}>
          Blocker</label>
        <button type="button" class="ho-del" data-kind="s" data-i="${i}"
                title="Delete this step">&times;</button>
      </div>
      ${s.kind==='uat' ? `<input class="ho-sr" list="ho_testers" data-i="${i}"
                 placeholder="who can test? (any, wizard 43+, level 60 melee…)"
                 value="${esc(s.tester||'')}">` : ''}
      <textarea class="ho-st" data-i="${i}"
                style="height:${hpx(s.step_h)}">${esc(s.step)}</textarea>
      ${s.kind==='uat' ? uatStepBarHTML(s, i) : ''}
    </div>`).join('');
  const paid = HO.uat_credits.filter(c=>c.awarded).length;
  const uc = HO.uat_credits.map((c,i)=>`
    <div class="ho-item ${c.awarded?'ho-done':''}">
      <div class="ho-row">
        <b style="flex:1">${esc(c.player)}</b>
        ${c.awarded
          ? `<span class="small">paid +1${c.date?' · '+esc(c.date):''}</span>
             <button type="button" class="ho-uatr" data-i="${i}"
                     title="Take the merit back">Revoke</button>`
          : `<button type="button" class="ho-uata" data-i="${i}"
                     title="Credit 1 merit in the live merit database">Award +1</button>`}
        <button type="button" class="ho-del" data-kind="u" data-i="${i}"
                title="Remove this validator">&times;</button>
      </div>
    </div>`).join('');
  const gates = [];
  if(open) gates.push(`${open} unanswered design question${open>1?'s':''}`);
  if(blocked) gates.push(`${blocked} unfinished blocker step${blocked>1?'s':''}`);
  el.innerHTML = `
    <div class="ho-panel">
      <div class="ho-head">Admin hand-off <span class="small">(internal — never shown
        on the public roadmap)</span></div>
      <label>Design questions ${open?`<span class="ho-badge">${open} open</span>`:''}</label>
      ${qs||'<p class="small">None.</p>'}
      <button type="button" id="ho_addq">+ Add question</button>
      <label style="margin-top:10px">Manual steps
        ${todo?`<span class="ho-badge">${todo} to do</span>`:''}
        ${blocked?`<span class="ho-badge">${blocked} blocking</span>`:''}
        ${failed?`<span class="ho-badge bad">${failed} failed</span>`:''}</label>
      <datalist id="ho_testers">${knownTesters().map(t=>
        `<option value="${esc(t)}">`).join('')}</datalist>
      ${ms||'<p class="small">None.</p>'}
      <button type="button" id="ho_adds">+ Add step</button>
      <label style="margin-top:10px">UAT validators
        ${paid?`<span class="ho-badge">${paid} paid</span>`:''}
        <span class="small">(1 merit each — anyone who helped verify the fix,
        not just the reporter)</span></label>
      ${uc||'<p class="small">None.</p>'}
      <button type="button" id="ho_addu">+ Add validator</button>
      ${commentsHTML()}
      ${gates.length?`<p class="small ho-gate">Autopilot will not resume this item:
        ${gates.join(' and ')}.</p>`:''}
    </div>`;
  $('#ho_addq').onclick = ()=>{
    HO.design_questions.push({question:'', status:'open', answer:null}); renderHandoff(); };
  $('#ho_adds').onclick = ()=>{
    HO.manual_steps.push({step:'', status:'open', kind:'admin', blocker:false,
                          tester:''}); renderHandoff(); };
  $('#ho_addu').onclick = ()=>addUatValidator();
  // Paying a UAT credit writes the shared merit DB. Adding and removing the
  // credit itself stays available to everyone -- only the payment is gated.
  el.querySelectorAll('.ho-uata, .ho-uatr').forEach(b=>{
    if (!CAN('merit')){
      b.disabled = true;
      b.title = 'Only an administrator can award or revoke merit';
    }
  });
  el.querySelectorAll('.ho-uata').forEach(b=>b.onclick = e=>
    uatAward(HO.uat_credits[+e.target.dataset.i].player, false));
  el.querySelectorAll('.ho-uatr').forEach(b=>b.onclick = e=>
    uatAward(HO.uat_credits[+e.target.dataset.i].player, true));
  el.querySelectorAll('.ho-qs').forEach(s=>s.onchange = e=>{
    HO.design_questions[+e.target.dataset.i].status = e.target.value; renderHandoff(); });
  el.querySelectorAll('.ho-ss').forEach(s=>s.onchange = e=>{
    HO.manual_steps[+e.target.dataset.i].status = e.target.value; renderHandoff(); });
  // Changing the kind re-renders: the tester input only exists on a uat step.
  el.querySelectorAll('.ho-sk').forEach(s=>s.onchange = e=>{
    HO.manual_steps[+e.target.dataset.i].kind = e.target.value; renderHandoff(); });
  el.querySelectorAll('.ho-sb').forEach(c=>c.onchange = e=>{
    HO.manual_steps[+e.target.dataset.i].blocker = e.target.checked; renderHandoff(); });
  // Mutate in place on input; do NOT re-render (it would steal focus mid-typing).
  el.querySelectorAll('.ho-qt').forEach(t=>t.oninput = e=>{
    HO.design_questions[+e.target.dataset.i].question = e.target.value; });
  el.querySelectorAll('.ho-qa').forEach(t=>t.oninput = e=>{
    HO.design_questions[+e.target.dataset.i].answer = e.target.value; });
  el.querySelectorAll('.ho-st').forEach(t=>t.oninput = e=>{
    HO.manual_steps[+e.target.dataset.i].step = e.target.value; });
  el.querySelectorAll('.ho-sr').forEach(t=>t.oninput = e=>{
    HO.manual_steps[+e.target.dataset.i].tester = e.target.value; });
  el.querySelectorAll('.ho-sres').forEach(t=>t.oninput = e=>{
    HO.manual_steps[+e.target.dataset.i].result = e.target.value; });
  // The three tester writes. Each posts a single step (or one comment) to its
  // own endpoint and then reloads, rather than joining the form's Save: a
  // tester has no `edit`, so /api/save would refuse them at the route table.
  el.querySelectorAll('.ho-claim').forEach(b=>b.onclick = e=>
    uatClaim(+e.target.dataset.i, false));
  el.querySelectorAll('.ho-release').forEach(b=>b.onclick = e=>
    uatClaim(+e.target.dataset.i, true));
  el.querySelectorAll('.ho-submit').forEach(b=>b.onclick = e=>
    uatSubmit(+e.target.dataset.i));
  const addc = $('#ho_addc');
  if (addc) addc.onclick = ()=>addComment();
  el.querySelectorAll('.ho-del').forEach(b=>b.onclick = e=>{
    const i = +e.target.dataset.i;
    syncHandoffHeights();
    if(e.target.dataset.kind==='q') HO.design_questions.splice(i,1);
    else if(e.target.dataset.kind==='u'){
      if(HO.uat_credits[i].awarded &&
         !confirm('“'+HO.uat_credits[i].player+'” has already been paid for this.'
           + '\n\nRemoving the row does NOT take the merit back — use Revoke '
           + 'for that. Remove anyway?')) return;
      HO.uat_credits.splice(i,1);
    }
    else HO.manual_steps.splice(i,1);
    renderHandoff(); });
  // The panel re-renders itself on every change, which resurrects the controls
  // select() disabled. Re-lock here or a read-only session gets a live form back
  // the first time anything in the panel redraws.
  lockFormIfReadOnly();
}

// ---- The tester lane: claim, report, comment ------------------------------
// All three go through one helper because they share a contract: one narrow
// write, then reload so the page shows what the server actually stored (these
// endpoints stamp fields the browser is not allowed to choose).
async function testerWrite(url, body, ok){
  const idea = DATA.ideas[sel]; if (!idea) return;
  try {
    const r = await api(url, {method:'POST',
      headers:{'Content-Type':'application/json'},
      body: JSON.stringify(Object.assign({id: idea.id}, body))});
    const d = await r.json();
    if (!d.ok){
      banner('err', (d.errors||[d.message||'refused']).join(' '));
      return;
    }
    banner('ok', d.message || ok);
    // Reload rather than patch in place: the server may have moved the status,
    // added a uat_credits row and stamped tested_by/tested_on in one write, and
    // guessing at that from here is how the two copies drift.
    const keep = idea.id;
    await load();
    const i = DATA.ideas.findIndex(x=>x.id===keep);
    if (i>=0) select(i);
  } catch(e){ banner('err', 'write failed: '+e.message); }
}

function uatClaim(i, release){
  const s = HO.manual_steps[i]; if(!s) return;
  testerWrite('/api/uat-claim', {index:i, step:(s.step||'').trim(),
                                 release: !!release},
              release ? 'Released.' : 'Claimed.');
}

function uatSubmit(i){
  const s = HO.manual_steps[i]; if(!s) return;
  const el = $('#handoff');
  const sel_ = el && el.querySelector('.ho-sresst[data-i="'+i+'"]');
  testerWrite('/api/uat-result',
              {index:i, step:(s.step||'').trim(),
               status: sel_ ? sel_.value : 'wip',
               result: (s.result||'').trim()},
              'Result recorded.');
}

function addComment(){
  const box = $('#ho_ctext'); if(!box) return;
  const text = box.value.trim();
  if (!text){ banner('err','Write something first.'); return; }
  testerWrite('/api/idea-comment', {text}, 'Note added.');
}

// ---- UAT validators: add a player, and pay/take back their 1 merit --------
// A UAT credit is independent of who reported the idea, so the picker is the
// whole meritdb roster (a tester may never have submitted anything), not the
// roadmap's own player list.
async function addUatValidator(){
  let res = {};
  try { res = await (await api('/api/meritplayers')).json(); } catch(e){ res={}; }
  const rows = res.rows || [];
  if (!rows.length){
    banner('bad', 'No merit database players to choose from'
      + (res.reason ? ' — '+res.reason : '') + '.');
    return;
  }
  const taken = new Set(HO.uat_credits.map(c=>(c.player||'').toLowerCase()));
  modalHTML(`<h2>Who helped validate this?</h2>
    <p class="small">They get <b>1 merit</b> for verifying the fix — whether or not
      they reported it. Add as many validators as you like; each is paid once.</p>
    <input id="uv_q" placeholder="Filter by name…" style="width:100%">
    <div id="uv_list" class="picklist"></div>
    <div class="bar"><span class="spacer"></span><button id="uv_close">Cancel</button></div>`);
  const draw = ()=>{
    const q = ($('#uv_q').value||'').toLowerCase();
    const hits = rows.filter(r=>!q || (r.name||'').toLowerCase().includes(q));
    $('#uv_list').innerHTML = hits.slice(0,200).map(r=>{
      const dupe = taken.has((r.name||'').toLowerCase());
      return `<div class="pick${dupe?' pick-off':''}" data-i="${rows.indexOf(r)}">
        <b>${esc(r.name||'(no name)')}</b>
        <span class="small">${dupe ? 'already listed'
          : 'balance '+r.balance+' · last login '+esc(r.last_login||'—')}</span></div>`;
    }).join('') || '<p class="small">No match.</p>';
    $('#uv_list').querySelectorAll('.pick').forEach(d=>{
      d.onclick = ()=>{
        const r = rows[+d.dataset.i];
        if (taken.has((r.name||'').toLowerCase())) return;
        closeModal();
        HO.uat_credits.push({player:r.name, awarded:false, date:''});
        renderHandoff();
      };
    });
  };
  $('#uv_q').oninput = draw;
  $('#uv_close').onclick = closeModal;
  draw();
  $('#uv_q').focus();
}

// Pay (or take back) one validator's merit. Like the submitter Award button,
// the live merit DB is written first and the YAML flag only moves if that
// succeeded — the server does both halves in one request.
function uatAward(who, revoke){
  const it = DATA.ideas[curIdx()]; if (!it) return;
  if (!confirm((revoke ? 'Take back the 1 merit point awarded to '
                       : 'Grant 1 merit point to ') + who
    + (revoke ? ' for validating this idea?' : ' for validating this idea?')
    + '\n\nThe game DB is written now; the roadmap only records it if that '
    + 'write succeeds.')) return;
  return commit(revoke ? '/api/uat-revoke' : '/api/uat-award', false,
                {stay:true, extra:{idea_id: it.id, player: who}});
}

// Drop blanks so an empty row never trips validation, and normalize answer.
function handoffOut(){
  syncHandoffHeights();
  const keepH = (o,src,keys)=>{ keys.forEach(k=>{ if(src[k]) o[k]=src[k]; }); return o; };
  const qs = HO.design_questions
    .filter(q=>(q.question||'').trim())
    .map(q=>keepH({question:q.question.trim(), status:q.status,
                   answer:(q.answer||'').trim()||null}, q, ['question_h','answer_h']));
  // `kind` is always emitted (normalize_step() defaults it anyway); `tester`
  // only when non-blank, matching normalize_step(), which drops a blank one.
  // HO_OWNED is everything the panel models — anything else on the step is a
  // key some other tool wrote, copied through verbatim the same way
  // pruneEmpty()/FORM_FIELDS does for an idea and emit_unknown() does in the
  // Python half. A save must never delete data it merely failed to recognise.
  const ms = HO.manual_steps
    .filter(s=>(s.step||'').trim())
    .map(s=>{
      const o = {};
      for (const k in s) if (HO_OWNED.indexOf(k)<0) o[k] = s[k];
      o.step = s.step.trim();
      o.status = s.status;
      o.kind = STEP_KINDS.indexOf(s.kind)>=0 ? s.kind : 'admin';
      o.blocker = !!s.blocker;
      const tester = (s.tester||'').trim();
      if (tester) o.tester = tester;
      // Emitted only when set, matching normalize_step()/emit_list_field(): a
      // step nobody has tested must serialize exactly as it did before these
      // fields existed, or every save churns the file.
      ['claimed_by','result','tested_by','tested_on'].forEach(k=>{
        const v = (s[k]||'').trim(); if (v) o[k] = v; });
      return keepH(o, s, ['step_h']);
    });
  const uc = HO.uat_credits
    .filter(c=>(c.player||'').trim())
    .map(c=>{ const o = {player:c.player.trim()};
              if(c.awarded) o.awarded = true;
              if(c.date) o.date = c.date;
              return o; });
  return {design_questions: qs.length?qs:null, manual_steps: ms.length?ms:null,
          uat_credits: uc.length?uc:null};
}

function readForm(){
  // Canonical value of each editor = whichever of its two views is active.
  const notes = RT.notes ? RT.notes.value() : '';
  const notes_h = RT.notes ? RT.notes.height() : 0;
  const impl = RT.impl ? RT.impl.value() : '';
  const impl_h = RT.impl ? RT.impl.height() : 0;
  const ho = handoffOut();
  return {
    id: $('#f_id').value.trim(),
    title: $('#f_title').value.trim(),
    group: $('#f_group').value,
    epic: $('#f_epic').value,
    status: $('#f_status').value,
    // Real boolean: pruneEmpty drops it when false so `hidden:` only ever
    // appears in the YAML on items that really are held back.
    hidden: $('#f_hidden').checked ? true : '',
    // Read-only here: no input owns it. It is set/cleared only by the Award and
    // Revoke buttons (which write meritdb first), so the form must carry the
    // live value straight through or an unrelated edit would silently clear it.
    merit_awarded: (selRef && selRef.merit_awarded) ? true : '',
    type: $('#f_type').value,
    player: $('#f_player').value.trim(),
    date: $('#f_date').value.trim(),
    commit: $('#f_commit').value.trim(),
    notes: notes,
    notes_h: (notes && notes_h && notes_h!==NOTES_DEFAULT_H) ? notes_h : '',
    impl_notes: impl,
    impl_notes_h: (impl && impl_h && impl_h!==IMPL_DEFAULT_H) ? impl_h : '',
    dupe_of: $('#f_dupe').value,
    // Internal admin-only fields, edited in the hand-off panel below Notes.
    design_questions: ho.design_questions,
    manual_steps: ho.manual_steps,
    uat_credits: ho.uat_credits,
  };
}

// Fields the form owns. Anything else an idea carries (a key written by some
// other tool that this editor doesn't model) is copied through from the loaded
// idea untouched — readForm() only knows about the form, so without this merge
// the unknown key would be gone before the save even leaves the browser.
// Mirrors emit_unknown()/serialize_ideas() in the Python half.
const FORM_FIELDS = ['id','title','group','epic','status','hidden','merit_awarded','type','player','date','commit','notes','notes_h','impl_notes','impl_notes_h','dupe_of','design_questions','manual_steps','uat_credits'];
function pruneEmpty(o, src){
  const r={};
  for (const k of FORM_FIELDS)
    if (o[k]!=='' && o[k]!=null) r[k]=o[k];
  for (const k in (src||{}))
    if (!FORM_FIELDS.includes(k)) r[k]=src[k];
  return r;
}

function banner(cls,msg){ const b=$('#banner'); b.className=cls; b.textContent=msg; }

// ---- unsaved-changes guard ----------------------------------------------
// The form lives entirely in the DOM until Save folds it into DATA, so anything
// that re-renders or hides it silently threw the edits away. Every navigation
// that would do that goes through guard().
function snapshot(){
  const i = curIdx();
  return (view==='list' && i>=0 && $('#f_id'))
    ? JSON.stringify(pruneEmpty(readForm(), DATA.ideas[i])) : null;
}
function isDirty(){
  // Fails open on purpose. If the comparison itself breaks (a half-rendered
  // form, an editor that hasn't initialised), the answer must be "not dirty":
  // a guard that throws would silently swallow every click and strand you on
  // one idea, which is far worse than losing the prompt.
  try {
    const now = snapshot();
    return now!==null && formSnapshot!==null && now!==formSnapshot;
  } catch(e){
    console.error('unsaved-changes check failed; treating form as clean', e);
    return false;
  }
}
// Run `action`, but if the open form has unsaved edits, ask first. `action`
// must resolve its target by id, not index: Save reloads the file first.
function guard(action){
  if (!isDirty()) return action();
  const it = DATA.ideas[curIdx()] || {};
  try {
  modalHTML(`<h2>Unsaved changes</h2>
    <p>“${esc(it.title || it.id || 'this idea')}” has edits that have not been
       written to roadmap.yaml.</p>
    <div class="bar">
      <button class="primary" id="g_save">Save and continue</button>
      <button class="danger" id="g_discard">Discard and continue</button>
      <span class="spacer"></span>
      <button id="g_cancel">Cancel — stay here</button>
    </div>`);
  $('#g_cancel').onclick = closeModal;
  $('#g_discard').onclick = ()=>{ closeModal(); formSnapshot=null; action(); };
  $('#g_save').onclick = async ()=>{
    closeModal();
    // Only navigate if the save actually landed — a validation error or a
    // write conflict must leave the edits on screen to be fixed.
    if (await commit('/api/save', false, {stay:true})) action();
  };
  } catch(e){
    // Same rule as isDirty(): if the prompt can't be shown, navigate anyway.
    console.error('unsaved-changes prompt failed; navigating anyway', e);
    action();
  }
}

// An uncaught error used to disappear into the console — invisible when the
// symptom is "the pane just stopped updating". Put it on screen.
window.addEventListener('error', e=>{
  try { banner('bad', 'JavaScript error: ' + (e.message || e.error)
    + (e.lineno ? ' (line '+e.lineno+')' : '')
    + '\nThe page may be in a bad state — reload it.'); } catch(_){}
});
window.addEventListener('unhandledrejection', e=>{
  try { banner('bad', 'JavaScript error (async): '
    + ((e.reason && e.reason.message) || e.reason)); } catch(_){}
});
// Select an idea after a possible reload: prefer its id, fall back to the row
// index for a brand-new idea that has no id yet.
function selectById(id, idx){
  const i = id ? DATA.ideas.findIndex(x=>x.id===id) : -1;
  select(i>=0 ? i : idx);
}
window.addEventListener('beforeunload', e=>{
  if (isDirty()){ e.preventDefault(); e.returnValue=''; }
});

// opts.stay  — hold the current idea selected instead of advancing to the next
//              visible row (pipeline buttons and the dirty-state guard: both
//              are mid-flow, and jumping the selection would be jarring).
// opts.extra — extra body fields for the endpoint (/api/award, /api/revoke).
// Returns true when the save landed.
async function commit(endpoint, force, opts){
  opts = opts || {};
  let keepId = (sel>=0 && DATA.ideas[sel]) ? DATA.ideas[sel].id : null;
  // Capture where we are in the *visible* (filtered + sorted) list so we can
  // advance to the next item there after the save reloads from the file, even
  // if the edit moved or dropped the current item out of the view.
  let nextId=null, curPos=-1;
  // In list view, fold the open form's edits into DATA before sending. In board
  // view there is no live form, so skip this (moveToStatus already mutated the
  // idea in place).
  if (view==='list' && $('#f_id')){
    // Resolve the open idea by identity, never by the (possibly stale) index.
    const idx = curIdx();
    if (idx < 0){
      banner('bad', 'The idea you were editing is no longer in the loaded file '
        + '(it was reloaded or removed elsewhere). Nothing was saved — reload '
        + 'the page and redo this edit.');
      return false;
    }
    // Renaming an idea onto another idea's id would overwrite that one here in
    // the browser and only fail server-side — by which point the overwritten
    // item has vanished from the page. Refuse up front instead.
    const formId = $('#f_id').value.trim();
    const clash = DATA.ideas.findIndex((x,j)=>j!==idx && x.id && x.id===formId);
    if (clash >= 0){
      banner('bad', 'Another idea already uses the id "'+formId+'" ("'
        + (DATA.ideas[clash].title||'') + '"). Nothing was saved — give this '
        + 'one a unique id.');
      return false;
    }
    sel = idx;   // re-sync the list highlight with what we are actually writing
    // Capture the next row from the list *as currently displayed*, BEFORE the
    // edit is applied — otherwise an edit that changes a sort key (status,
    // group, title…) re-sorts the current item and "next" is taken relative to
    // its new position, making the selection jump somewhere unexpected.
    const vis = visibleRows();
    curPos = vis.findIndex(r=>r.idx===idx);
    if (curPos>=0 && curPos+1<vis.length) nextId = vis[curPos+1].it.id;
    DATA.ideas[idx] = pruneEmpty(readForm(), DATA.ideas[idx]);
    selRef = DATA.ideas[idx];
    keepId = DATA.ideas[idx].id || keepId;   // follow a renamed id
  }
  const r = await api(endpoint, {method:'POST',
    headers:{'Content-Type':'application/json'},
    body: JSON.stringify(Object.assign(
      {ideas: DATA.ideas, groups: DATA.vocab.groups,
       players: DATA.vocab.players, epics: DATA.vocab.epics,
       base_version: baseVersion, base_hashes: baseHashes,
       base_vocab: baseVocab, force: !!force}, opts.extra||{}))});
  const res = await r.json();
  if (res.version) baseVersion = res.version;   // rebase our baseline
  if (res.conflict){ conflictBanner(endpoint, res.message); return false; }
  if (!res.ok){
    banner('bad', 'Not saved:\n• ' + (res.errors||['unknown error']).join('\n• ')
      + (res.warnings&&res.warnings.length ? '\n\nWarnings:\n• '+res.warnings.join('\n• '):''));
    // A failed merit award/revoke still writes the file (with the status put
    // back), so re-read it rather than leave the page showing a state the file
    // never had.
    if (res.reverted !== undefined){ await load(); reselect(keepId); }
    return false;
  }
  let msg = res.message || 'Saved.';
  if (res.warnings && res.warnings.length) msg += '\n\nWarnings:\n• '+res.warnings.join('\n• ');
  if (res.output) msg += '\n\n'+res.output;
  banner(res.warnings&&res.warnings.length ? 'warn':'ok', msg);
  await load();
  if (view!=='list') return true;
  if (opts.stay) reselect(keepId); else advanceSelection(nextId, curPos);
  return true;
}

// Re-select an idea by id after a reload (indices shift when the file is
// re-read, so nothing may be held across a load() but the id).
function reselect(id){
  const i = id ? DATA.ideas.findIndex(x=>x.id===id) : -1;
  if (i>=0) select(i);
  else { sel=-1; selRef=null; formSnapshot=null; renderList(); $('#form').innerHTML=''; }
}

// External-edit conflict: the file changed on disk since we loaded it. Offer to
// Reload the latest (losing in-page edits) or Force-overwrite it.
function conflictBanner(endpoint, conflictMsg){
  const b=$('#banner'); b.className='warn';
  b.innerHTML='';
  const msg=document.createElement('div');
  msg.textContent = conflictMsg
    || '⚠ roadmap.yaml changed on disk since you opened it (external edit '
       + 'detected). Reload to pull those changes, or Force save to overwrite them.';
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
  else { sel=-1; selRef=null; renderList(); $('#form').innerHTML=''; }
}

function move(dir){
  const i = curIdx(); if (i<0) return;
  DATA.ideas[i] = pruneEmpty(readForm(), DATA.ideas[i]);
  const j = i+dir; if (j<0||j>=DATA.ideas.length) return;
  [DATA.ideas[i],DATA.ideas[j]]=[DATA.ideas[j],DATA.ideas[i]];
  sel=j; renderList(); select(sel);
}

function del(){
  const i = curIdx(); if (i<0) return;
  if (!confirm('Delete this idea from the backlog?')) return;
  DATA.ideas.splice(i,1);
  sel = Math.min(i, DATA.ideas.length-1);
  renderList();
  if (sel>=0) select(sel); else { selRef=null; $('#form').innerHTML=''; }
  banner('warn','Deleted in the editor. Click Save to write it to roadmap.yaml.');
}

$('#add').onclick = ()=>guard(()=>{
  const g = DATA.vocab.groups[0] ? DATA.vocab.groups[0].id : '';
  DATA.ideas.unshift({id:'', title:'', group:g, status:'planned'});
  // Adding needs the full form (id + title), so always land in list view.
  if (view!=='list'){ setView('list'); }
  sel=0; renderList(); select(0);
  banner('warn','New idea added. Give it a unique id + title, then Save.');
});

// ---- group / player management modals -----------------------------------
const escAmp = s => s.replace(/&/g,'&amp;');          // store titles in YAML form
const dispAmp = s => (s||'').replace(/&amp;/g,'&');   // ...show them un-escaped
function modalHTML(html){ $('#modalbox').innerHTML=html; $('#modal').classList.add('show'); }
function closeModal(){ $('#modal').classList.remove('show'); }
$('#modal').onclick = e=>{ if(e.target.id==='modal') closeModal(); };

// Palette Finder: search where a blueprint lives in the toolset palette.
let pfTimer=null;
// ---- LLM change review -----------------------------------------------
// Everything a model wrote into this repo, worst-first. Ordering comes from the
// priority score each task recipe computed at generation time; nothing here
// re-asks a model anything.
let LC = {showDone:false, task:'', data:null, mode:'batch'};

function lcRowHTML(row){
  const warn = row.warnings.length
    ? `<div class="lc-warn">! ${row.warnings.map(esc).join(' · ')}</div>` : '';
  const before = (row.before===null || row.before===undefined || row.before==='')
    ? '<span class="lc-before">(was empty)</span>'
    : `<div class="lc-before">${esc(String(row.before))}</div>`;
  const done = row.review!=='pending';
  const rr = row.item
    ? `<button class="rr" data-act="reroll" data-engine="gemma" data-id="${row.id}">↻ Gemma</button>
       <button class="rr" data-act="reroll" data-engine="sonnet" data-id="${row.id}">↻ Sonnet</button>`
    : '';
  const acts = done
    ? `<span class="small">${esc(row.review)}</span>
       <button data-act="revert" data-id="${row.id}">Revert</button>${rr}`
    : `<button data-act="approve" data-id="${row.id}">Approve</button>
       <button data-act="edit" data-id="${row.id}">Edit</button>
       <button data-act="revert" data-id="${row.id}">Revert</button>${rr}`;
  // Which model wrote this. A batch is mostly Gemma with the odd Sonnet
  // recovery in it, so the source belongs on the ROW -- the group header can
  // only name one and would misreport every fallback in the batch.
  const src = row.source||'';
  const srcCls = src.indexOf('sonnet')===0 ? 'lc-src sonnet' : 'lc-src';
  return `<div class="lc-row ${done?'lc-done':''}">
    <div class="lc-file">${esc(row.file)} <span class="small">${esc(row.field)}</span>
      ${src?`<span class="${srcCls}">· ${esc(src)}</span>`:''}
      ${row.priority?`<span class="small">· p=${row.priority}</span>`:''}
      ${row.confidence!=null?`<span class="small">· conf ${row.confidence}</span>`:''}</div>
    ${before}
    <div class="lc-after">${esc(String(row.after??''))}</div>
    ${warn}
    <div class="lc-acts">${acts}</div>
  </div>`;
}

// ---- compare view: one item, its stats, both halves of its description ----
// Reviewing prose about an object without seeing the object is guesswork, so
// every row carries the item's real property list with each value's standing
// among all items of its kind in this module.
function lcPropsHTML(item){
  if(!item) return '<div class="small">no item stats available</div>';
  const rows = (item.properties||[]).map(p=>{
    const i = p.indexOf(' -- ');
    if(i<0) return `<li>${esc(p)}</li>`;
    const rank = p.slice(i+4);
    const cls = /nothing in the world|very greatest/.test(rank) ? 'rank-top' : 'rankw';
    return `<li>${esc(p.slice(0,i))} <span class="${cls}">${esc(rank)}</span></li>`;
  }).join('');
  const link = item.wiki_url
    ? ` &middot; <a href="${esc(item.wiki_url)}" target="_blank">wiki</a>` : '';
  return `<div class="lc-props">
    <div class="small"><b>${esc(item.base_item||'')}</b> &middot;
      tier <b>${esc(item.overall_tier||'')}</b> &middot;
      value ${esc(item.gold_tier||'')}${link}</div>
    <ul style="margin:6px 0 0;padding:0">${rows||'<li class="lc-empty">no properties</li>'}</ul>
    ${(item.sources||[]).length?`<div class="small" style="margin-top:6px">${esc(item.sources[0])}</div>`:''}
  </div>`;
}

function lcHalfHTML(half, label){
  if(!half) return `<div class="lc-half"><div class="lbl">${label}</div>
    <div class="lc-empty">not written yet</div></div>`;
  const src = half.source||'';
  const srcCls = src.indexOf('sonnet')===0 ? 'lc-src sonnet' : 'lc-src';
  const warn = half.warnings.length
    ? `<div class="lc-warn">! ${half.warnings.map(esc).join(' · ')}</div>` : '';
  const acts = half.id
    ? `<div class="lc-acts">
         ${half.review==='pending'?`<button data-act="approve" data-id="${half.id}">Approve</button>`:''}
         <button data-act="edit" data-id="${half.id}">Edit</button>
         <button data-act="revert" data-id="${half.id}">Revert</button>
         <button class="rr" data-act="reroll" data-engine="gemma"
                 data-id="${half.id}" title="Generate a fresh one on the local Gemma box">↻ Gemma</button>
         <button class="rr" data-act="reroll" data-engine="sonnet"
                 data-id="${half.id}" title="Generate a fresh one with Claude Sonnet (uses your Claude subscription)">↻ Sonnet</button>
       </div>`
    : `<div class="lc-acts">
         <span class="small">no ledger record — edited outside the panel</span>
         <button data-act="adopt" data-file="${esc(half.file||'')}"
                 data-field="${esc(half.field)}"
                 title="Record this text as-is so it can be approved and tracked">Keep this</button>
         <button class="rr" data-act="reroll-field" data-engine="gemma"
                 data-file="${esc(half.file||'')}" data-field="${esc(half.field)}">↻ Gemma</button>
         <button class="rr" data-act="reroll-field" data-engine="sonnet"
                 data-file="${esc(half.file||'')}" data-field="${esc(half.field)}">↻ Sonnet</button>
       </div>`;
  return `<div class="lc-half filled">
    <div class="lbl">${label}
      <span class="${srcCls}">${esc(src)}</span>
      ${half.review!=='pending'?`<span class="small">· ${esc(half.review)}</span>`:''}</div>
    <div class="txt">${esc(half.text)}</div>
    ${warn}${acts}
  </div>`;
}

function lcCompareHTML(rows){
  return rows.map(r=>{
    const name = (r.item && r.item.name) || r.file.split('/').pop();
    return `<div class="lc-item">
      <h3>${esc(name)} <span class="small">${esc(r.file)}</span></h3>
      <div class="lc-body">
        ${lcPropsHTML(r.item)}
        <div class="lc-halves">
          ${lcHalfHTML(r.unidentified,'Unidentified — before the player identifies it')}
          ${lcHalfHTML(r.identified,'Identified — what they read after')}
        </div>
      </div>
    </div>`;
  }).join('');
}

function lcRender(){
  const box=$('#lc_results'), meta=$('#lc_meta');
  if(!box) return;
  const d=LC.data;
  if(!d){ box.innerHTML='<p class="small">Loading…</p>'; return; }
  if(d.unavailable){
    meta.textContent='';
    box.innerHTML='<p class="small">The <code>bin/llm</code> harness is not installed '+
      'on this checkout, so there is nothing to review.</p>'; return;
  }
  meta.textContent = d.pending+' pending of '+d.total+' recorded'+
    (d.truncated?' (showing the first '+d.shown+')':'');
  if(d.mode==='compare'){
    box.innerHTML = d.rows.length
      ? lcCompareHTML(d.rows)
      : '<p class="small">Nothing to compare.</p>';
    return;
  }
  if(!d.groups.length){
    box.innerHTML='<p class="small">Nothing to review. '+
      (d.total?'Tick "show reviewed" to see what has already been handled.'
             :'Run a task with <code>python3 bin/llm/run.py &lt;task&gt; --apply</code> first.')+
      '</p>'; return;
  }
  box.innerHTML = d.groups.map(g=>{
    const ids = g.rows.filter(r=>r.review==='pending').map(r=>r.id);
    const bulk = ids.length
      ? `<button data-act="approve_group" data-ids="${ids.join(',')}">Approve all ${ids.length}</button>`
      : '';
    return `<div class="lc-group lc-risk-${esc(g.risk)}">
      <h3>${esc(g.task)} · ${esc(g.risk)} · ${g.count} change${g.count===1?'':'s'}
        ${g.flagged?`<span class="lc-warn">(${g.flagged} flagged)</span>`:''}</h3>
      <div class="small">${esc(g.batch)} · ${esc(g.sources||g.source||'')} · ${esc(g.ts||'')}</div>
      <div class="lc-acts">${bulk}</div>
      ${g.rows.map(lcRowHTML).join('')}
    </div>`;
  }).join('');
}

async function lcLoad(){
  const qs='/api/changes?done='+(LC.showDone?'1':'0')+'&task='+encodeURIComponent(LC.task)
    +'&mode='+LC.mode;
  const r=await fetch(qs);
  LC.data=await r.json();
  lcRender();
}

async function lcAct(body){
  body.show_done=LC.showDone; body.task=LC.task; body.mode=LC.mode;
  const r=await api('/api/changes/action',
    {method:'POST',headers:{'Content-Type':'application/json'},body:JSON.stringify(body)});
  const res=await r.json();
  banner(res.ok?'ok':'bad', res.message||'');
  if(res.ok){ LC.data=res; lcRender(); }
}

function openChanges(){
  modalHTML(`<h2>LLM Changes</h2>
    <p class="small">Every field a model wrote into <code>unpacked/</code>, recorded in
      <code>llm-changes/*.jsonl</code>. Sorted worst-first by the priority the task
      recipe computed — validator warnings, near-duplicate score and the model's own
      confidence. <b>Revert</b> restores the previous value on disk; <b>Edit</b> replaces
      it with your own text. Both are recorded, so nothing is lost either way.</p>
    <div class="lc-bar">
      <select id="lc_mode">
        <option value="batch">by batch</option>
        <option value="compare">by item (both descriptions + stats)</option>
      </select>
      <select id="lc_task"><option value="">all tasks</option></select>
      <label class="small"><input type="checkbox" id="lc_done"> show reviewed</label>
      <span class="pf-meta" id="lc_meta"></span>
    </div>
    <div id="lc_results"></div>
    <div class="bar"><span class="spacer"></span><button id="lc_close">Close</button></div>`);
  $('#modalbox').classList.add('wide');
  $('#lc_close').onclick=closeModal;
  $('#lc_done').checked=LC.showDone;
  $('#lc_done').onchange=e=>{ LC.showDone=e.target.checked; lcLoad(); };
  $('#lc_task').onchange=e=>{ LC.task=e.target.value; lcLoad(); };
  $('#lc_mode').value=LC.mode;
  $('#lc_mode').onchange=e=>{
    LC.mode=e.target.value;
    $('#lc_task').disabled = (LC.mode==='compare');   // compare spans tasks
    lcLoad();
  };
  $('#lc_task').disabled = (LC.mode==='compare');
  // Delegated so the handlers survive every re-render.
  $('#lc_results').addEventListener('click', async e=>{
    const b=e.target.closest('button[data-act]'); if(!b) return;
    const act=b.dataset.act;
    if(act==='approve_group'){
      const ids=b.dataset.ids.split(',');
      if(!confirm('Approve all '+ids.length+' changes in this group?')) return;
      return lcAct({action:'approve_group', ids});
    }
    if(act==='revert'){
      if(!confirm('Restore the previous value on disk?')) return;
      return lcAct({action:'revert', id:b.dataset.id});
    }
    if(act==='adopt'){
      return lcAct({action:'adopt', file:b.dataset.file, field:b.dataset.field});
    }
    if(act==='reroll'||act==='reroll-field'){
      // A roll takes ~5-20s on Gemma. Disable the row's buttons and say so,
      // or an impatient second click queues a second generation.
      const engine=b.dataset.engine;
      const row=b.closest('.lc-acts');
      const olds=[...row.querySelectorAll('button')].map(x=>[x,x.textContent]);
      olds.forEach(([x])=>x.disabled=true);
      b.textContent='rolling…';
      try {
        await lcAct(b.dataset.id
          ? {action:'reroll', id:b.dataset.id, engine}
          : {action:'reroll', file:b.dataset.file, field:b.dataset.field, engine});
      } finally {
        olds.forEach(([x,txt])=>{ x.disabled=false; x.textContent=txt; });
      }
      return;
    }
    if(act==='edit'){
      const row=b.closest('.lc-row');
      const cur=row.querySelector('.lc-after').textContent;
      const text=prompt('Replace the generated text with:', cur);
      if(text===null) return;
      return lcAct({action:'edit', id:b.dataset.id, text});
    }
    return lcAct({action:act, id:b.dataset.id});
  });
  lcLoad().then(()=>{
    const sel=$('#lc_task');
    if(sel && LC.data && LC.data.tasks){
      LC.data.tasks.forEach(t=>{
        const o=document.createElement('option'); o.value=t; o.textContent=t;
        sel.appendChild(o);
      });
      sel.value=LC.task;
    }
  });
}

function openPalette(){
  modalHTML(`<h2>Palette Finder</h2>
    <p class="small">Search a creature/item/placeable by name (or resref) and see
      where it lives in the in-game toolset palette. The map is built by
      <code>bin/gen-palette-map.py</code> — a standalone script, not the wiki
      build. Click <b>Refresh</b> after adding or moving blueprints.</p>
    <div class="pf-bar">
      <input id="pf_q" placeholder="search name or resref…" autocomplete="off">
      <button id="pf_refresh">Refresh palette map</button>
    </div>
    <div class="pf-bar" style="margin-top:0;">
      <span class="pf-meta" id="pf_meta"></span>
    </div>
    <div id="pf_results"></div>
    <div class="bar"><span class="spacer"></span><button id="pf_close">Close</button></div>`);
  $('#pf_close').onclick=closeModal;
  const q=$('#pf_q');
  q.oninput=()=>{ clearTimeout(pfTimer); pfTimer=setTimeout(pfSearch, 180); };
  $('#pf_refresh').onclick=async()=>{
    const b=$('#pf_refresh'); b.disabled=true; const old=b.textContent;
    b.textContent='Refreshing…';
    try{
      const r=await api('/api/palette/refresh',
        {method:'POST',headers:{'Content-Type':'application/json'},body:'{}'});
      const res=await r.json();
      banner(res.ok?'ok':'bad', (res.message||'') + (res.output?'\n\n'+res.output:''));
      pfSearch();
    } finally { b.disabled=false; b.textContent=old; }
  };
  q.focus();
  pfSearch();
}
async function pfSearch(){
  const term=$('#pf_q') ? $('#pf_q').value.trim() : '';
  const r=await api('/api/palette?q='+encodeURIComponent(term));
  const d=await r.json();
  const meta=$('#pf_meta'), box=$('#pf_results');
  if(!meta||!box) return;
  if(!d.built){
    meta.textContent='Palette map not built yet — click "Refresh palette map".';
    box.innerHTML=''; return;
  }
  meta.textContent = (term
      ? d.matched+' match'+(d.matched===1?'':'es')+' of '+d.total
      : d.total+' blueprints indexed')
    + ' · built '+ (d.built||'').replace('T',' ');
  if(!term){ box.innerHTML='<p class="small">Type to search…</p>'; return; }
  if(!d.results.length){ box.innerHTML='<p class="small">No matches.</p>'; return; }
  box.innerHTML='<table><thead><tr><th>Name</th><th>Type</th>'
    +'<th>Palette location</th><th>Section</th><th>ResRef</th></tr></thead><tbody>'
    + d.results.map(e=>{
        const sect = e.in_palette===false ? ''
          : (e.custom_palette ? '<span class="pf-custom">Custom</span>'
                              : '<span class="pf-std">Standard</span>');
        return '<tr><td>'+esc(e.name)+'</td>'
          +'<td class="pf-type">'+esc(e.type)+'</td>'
          +'<td class="'+(e.in_palette===false?'pf-orphan':'pf-path')+'">'
            +esc(e.palette||'—')+'</td>'
          +'<td>'+sect+'</td>'
          +'<td class="pf-rr">'+esc(e.resref)+'</td></tr>';
      }).join('')
    + '</tbody></table>';
}

// ---- work queues: Toolset Queue / UAT Queue -------------------------------
// The hand-off panel shows one idea's steps. These show one KIND of step across
// the whole backlog, which is what you actually want when you are sitting in
// the toolset (place these waypoints, tune these portraits) or in the game
// client (run these checks, and on what character). Rows are read straight from
// DATA.ideas — no new read endpoint — and each control writes just its own step
// through /api/step-status.
const STEP_KINDS = ['toolset','uat','admin'];
let QUEUE = {kind:'toolset', filter:'', showDone:false, showAwarded:false,
             mine:false};

// Every step of the wanted kinds, flattened, with its owning idea.
function queueRows(kinds){
  const out=[];
  DATA.ideas.forEach(it=>{
    if (it.hidden) return;
    // Merit-awarded ideas are finished business; their leftover steps would
    // otherwise sit in the queue forever. `implemented`/`manual` still show —
    // those are the shipped-but-in-testing items the UAT queue exists for.
    if (!QUEUE.showAwarded && it.status==='awarded') return;
    (it.manual_steps||[]).forEach((s,i)=>{
      if (!s || typeof s!=='object') return;
      const k = STEP_KINDS.indexOf(s.kind)>=0 ? s.kind : 'admin';
      if (kinds.indexOf(k)<0) return;
      if (!QUEUE.showDone && s.status==='done') return;
      // "Only mine" is what turns this from a backlog into a worklist for a
      // tester who has claimed a handful of checks.
      if (QUEUE.mine && !isMine(s.claimed_by||'')) return;
      out.push({idea:it, step:s, index:i, kind:k});
    });
  });
  // Blockers first, then failed (needs another code change) before unstarted
  // before in-progress, then by idea title.
  const rank = s => s.status==='done' ? 3
    : (s.status==='failed' ? 0 : (s.status==='wip' ? 1 : 2));
  out.sort((a,b)=> (b.step.blocker?1:0)-(a.step.blocker?1:0)
                || rank(a.step)-rank(b.step)
                || String(a.idea.title||'').localeCompare(String(b.idea.title||'')));
  return out;
}

function testerKey(s){ return (s.tester||'').trim(); }

// Distinct tester values already in use — the datalist that keeps "wizard 43+"
// from becoming four spellings of the same requirement.
function knownTesters(){
  const seen=new Map();
  DATA.ideas.forEach(it=>(it.manual_steps||[]).forEach(s=>{
    const t = s && typeof s==='object' ? testerKey(s) : '';
    if (t && !seen.has(t.toLowerCase())) seen.set(t.toLowerCase(), t);
  }));
  return [...seen.values()].sort((a,b)=>a.localeCompare(b));
}

function queueRowHTML(r, withTester){
  const s=r.step, g=(DATA.vocab.groups.find(x=>x.id===r.idea.group)||{}).title||r.idea.group||'';
  const sel = v => `<select class="q_status" data-id="${esc(r.idea.id)}" data-i="${r.index}">`
    + STEP_ORDER.map(o=>`<option value="${o}"${v===o?' selected':''}>`
        + QSTEP_LABEL[o] + '</option>').join('')
    + '</select>';
  const kindSel = `<select class="q_kind" data-id="${esc(r.idea.id)}" data-i="${r.index}">`
    + STEP_KINDS.map(k=>`<option value="${k}"${r.kind===k?' selected':''}>${k}</option>`).join('')
    + '</select>';
  const tester = withTester
    ? `<input class="tester q_tester" list="q_testers" placeholder="who can test?"
              value="${esc(testerKey(s))}" data-id="${esc(r.idea.id)}" data-i="${r.index}">`
    : '';
  // The status/kind/tester controls all write through /api/step-status, which
  // needs `edit`. A tester gets the claim + result pair instead: same row, a
  // different (and much narrower) endpoint behind it.
  const admin = CAN('edit') ? `${tester}${kindSel}${sel(s.status||'open')}` : '';
  const held = (s.claimed_by||'').trim();
  const stamp = (s.tested_by||'').trim()
    ? `<span class="qsub">reported by ${esc(s.tested_by)}${
         s.tested_on?' · '+esc(s.tested_on):''}</span>` : '';
  let mineBits = '';
  if (withTester && CAN('uat')){
    const claimBtn = !held
      ? `<button class="q_claim" data-id="${esc(r.idea.id)}" data-i="${r.index}"
                 >Claim</button>`
      : ((isMine(held) || CAN('edit'))
          ? `<button class="q_release" data-id="${esc(r.idea.id)}" data-i="${r.index}"
                     >Release</button>` : '');
    mineBits = `
      <div class="qctl qclaim">
        ${held?`<span class="ho-chip${isMine(held)?' me':''}">claimed by ${esc(held)}</span>`
              :'<span class="qsub">unclaimed</span>'}
        ${claimBtn}
        <button class="q_open" data-goto="${esc(r.idea.id)}"
                title="Open the item to write up what you found">Report…</button>
        ${stamp}
      </div>`;
  }
  return `<div class="qrow${s.status==='done'?' done':(s.status==='failed'?' failed':'')}">
    <div class="qmeta">
      <button class="qtitle" data-goto="${esc(r.idea.id)}">${esc(r.idea.title||r.idea.id)}</button>
      <span class="qsub">${esc(dispAmp(g))}${s.blocker?' · <span class="qblock">BLOCKER</span>':''}${s.status==='failed'?' · <span class="qfail">FAILED</span>':''}</span>
    </div>
    <div class="qtext">${esc(s.step||'')}</div>
    ${admin?`<div class="qctl">${admin}</div>`:''}
    ${mineBits}
    ${(s.result||'').trim()?`<div class="qtext qresult">${esc(s.result)}</div>`:''}
  </div>`;
}

// Plain-text version of what is on screen — for pasting into a toolset session
// or a notes file, where a browser tab is not welcome.
function queueChecklist(groups){
  return groups.map(([label, rows]) => label + '\n'
    + rows.map(r=>'  [ ] ' + (r.step.blocker?'(BLOCKER) ':'')
        + (r.step.status==='failed'?'(FAILED) ':'')
        + (testerKey(r.step)?'('+testerKey(r.step)+') ':'')
        + (r.idea.title||r.idea.id) + ' — '
        + String(r.step.step||'').replace(/\s+/g,' ')).join('\n')
  ).join('\n\n');
}

function renderQueue(){
  const box=$('#qresults'); if(!box) return;
  const uat = QUEUE.kind==='uat';
  const rows = queueRows(uat ? ['uat'] : ['toolset'])
    .filter(r=>{
      const f=QUEUE.filter.toLowerCase(); if(!f) return true;
      return (r.step.step||'').toLowerCase().includes(f)
          || (r.idea.title||'').toLowerCase().includes(f)
          || testerKey(r.step).toLowerCase().includes(f);
    });
  // UAT groups by who can run the check; toolset groups by toolset vs deploy.
  const buckets=new Map();
  rows.forEach(r=>{
    const key = uat ? (testerKey(r.step) || 'Any / unspecified') : 'Toolset';
    if(!buckets.has(key)) buckets.set(key, []);
    buckets.get(key).push(r);
  });
  const order=[...buckets.entries()].sort((a,b)=>{
    // "Any / unspecified" last: it is the triage pile, not the work.
    const la=a[0]==='Any / unspecified', lb=b[0]==='Any / unspecified';
    return (la?1:0)-(lb?1:0) || a[0].localeCompare(b[0]);
  });
  $('#q_count').textContent = rows.length + (rows.length===1?' step':' steps')
    + (QUEUE.showDone?' (including done)':' outstanding')
    + (QUEUE.showAwarded?'':' · awarded ideas hidden');
  box.innerHTML = order.length
    ? order.map(([label,rs])=>`<div class="qgroup">${esc(label)}
        <span class="n">${rs.length}</span></div>`
        + rs.map(r=>queueRowHTML(r, uat)).join('')).join('')
    : '<p class="small">Nothing here. '
      + (QUEUE.filter?'No step matches that filter.':'Queue is clear.') + '</p>';
  box.dataset.plain = queueChecklist(order);
}

async function stepWrite(id, index, patch){
  const it = DATA.ideas.find(x=>x.id===id);
  const s = it && (it.manual_steps||[])[index];
  if (!s) return;
  const body = Object.assign({id, index, step: s.step}, patch);
  const r = await api('/api/step-status',
    {method:'POST', headers:{'Content-Type':'application/json'},
     body: JSON.stringify(body)});
  const res = await r.json();
  if (!res.ok){
    banner('bad', res.message || (res.errors||[]).join('\n') || 'Step update failed.');
    return;
  }
  Object.assign(s, patch);           // keep the in-memory copy in step
  baseVersion = res.version || baseVersion;
  // Rebase the per-idea merge baseline too. Rebasing baseVersion alone is what
  // made these ticks vanish: with the versions equal, /api/save skips the
  // three-way merge and writes the page's document wholesale — including the
  // hand-off panel's HO, a snapshot of this idea's steps taken back when the
  // form was opened, which still says every step is open.
  if (res.hashes && baseHashes) Object.assign(baseHashes, res.hashes);
  // …and that snapshot has to be refreshed, or the very next Save undoes this
  // write. formSnapshot follows it so the unsaved-changes guard keeps measuring
  // against what is really on screen.
  if (selRef && selRef.id === id){ initHandoff(selRef); formSnapshot = snapshot(); }
  renderQueue();
}

// Claim/release from the queue. Deliberately not stepWrite(): that posts to
// /api/step-status, which needs `edit`. This is the tester's own endpoint, and
// it is the reason the queue is usable by a role that cannot save.
async function queueClaim(id, index, release){
  const it = DATA.ideas.find(x=>x.id===id);
  const s = it && (it.manual_steps||[])[index];
  if (!s) return;
  try {
    const r = await api('/api/uat-claim',
      {method:'POST', headers:{'Content-Type':'application/json'},
       body: JSON.stringify({id, index, step:s.step, release: !!release})});
    const res = await r.json();
    if (!res.ok){
      banner('bad', res.message || (res.errors||[]).join('\n') || 'Claim failed.');
      return;
    }
    // The server may have moved the status as well as the claim, so take its
    // copy of the idea rather than patching two fields and hoping.
    if (res.idea) Object.assign(it, res.idea);
    baseVersion = res.version || baseVersion;
    if (res.hashes && baseHashes) Object.assign(baseHashes, res.hashes);
    if (selRef && selRef.id === id){ initHandoff(selRef); formSnapshot = snapshot(); }
    banner('ok', res.message || 'Done.');
    renderQueue();
  } catch(e){ banner('bad', 'Claim failed: '+e.message); }
}

function openQueue(kind){
  QUEUE = {kind, filter:'', showDone:false, showAwarded:false, mine:false};
  const uat = kind==='uat';
  modalHTML(`<h2>${uat?'UAT Queue':'Toolset Queue'}</h2>
    <p class="small">${uat
      ? 'Every shipped item still waiting on an in-game check, grouped by the '
        + 'character it takes to run it. Fill in <b>who can test</b> on anything '
        + 'in “Any / unspecified” — that is what the grouping is for, and it is '
        + 'what players see on the Recent Updates sign.'
      : 'Everything outstanding that needs the toolset (waypoints, palette, '
        + 'appearance, portraits, voicesets) or a deploy. Ticking a step here '
        + 'writes roadmap.yaml immediately — it does not regenerate or publish.'}</p>
    <div class="qbar">
      <input id="q_filter" placeholder="filter…" autocomplete="off">
      <label class="chk"><input type="checkbox" id="q_done"> show done</label>
      <label class="chk"><input type="checkbox" id="q_awarded"> show awarded ideas</label>
      ${uat && CAN('uat') && ME()
        ? '<label class="chk"><input type="checkbox" id="q_mine"> only mine</label>'
        : ''}
      <button id="q_copy">Copy as checklist</button>
    </div>
    <div class="qbar" style="margin-top:0;"><span class="pf-meta" id="q_count"></span></div>
    <datalist id="q_testers">${knownTesters().map(t=>`<option value="${esc(t)}">`).join('')}</datalist>
    <div id="qresults"></div>
    <div class="bar"><span class="spacer"></span><button id="q_close">Close</button></div>`);
  $('#modalbox').classList.add('wide');
  $('#q_close').onclick=()=>{ $('#modalbox').classList.remove('wide'); closeModal(); };
  $('#q_filter').oninput=e=>{ QUEUE.filter=e.target.value.trim(); renderQueue(); };
  $('#q_done').onchange=e=>{ QUEUE.showDone=e.target.checked; renderQueue(); };
  $('#q_awarded').onchange=e=>{ QUEUE.showAwarded=e.target.checked; renderQueue(); };
  const qm=$('#q_mine');
  if (qm) qm.onchange=e=>{ QUEUE.mine=e.target.checked; renderQueue(); };
  $('#q_copy').onclick=()=>{
    const txt=$('#qresults').dataset.plain||'';
    navigator.clipboard.writeText(txt).then(
      ()=>banner('ok','Checklist copied to the clipboard.'),
      ()=>banner('bad','Could not reach the clipboard — copy from the page instead.'));
  };
  // Delegated so the handlers survive every re-render.
  $('#qresults').addEventListener('change', e=>{
    const t=e.target, id=t.dataset.id, i=+t.dataset.i;
    if (t.classList.contains('q_status')) stepWrite(id, i, {status:t.value});
    else if (t.classList.contains('q_kind')) stepWrite(id, i, {kind:t.value});
    else if (t.classList.contains('q_tester')) stepWrite(id, i, {tester:t.value});
  });
  $('#qresults').addEventListener('click', e=>{
    const c=e.target.closest('.q_claim, .q_release');
    if (c){
      queueClaim(c.dataset.id, +c.dataset.i, c.classList.contains('q_release'));
      return;
    }
    const b=e.target.closest('[data-goto]'); if(!b) return;
    $('#modalbox').classList.remove('wide'); closeModal();
    guard(()=>{ if (view!=='list') setView('list'); selectById(b.dataset.goto, -1); });
  });
  renderQueue();
  $('#q_filter').focus();
}

// ---- UAT Review: the admin's side of the tester lane ----------------------
// A tester records a result and lands an UNPAID uat_credits row (see
// _uat_result in the Python half). This is where those get read and paid.
//
// No read endpoint: /api/data already carries the whole document, so the panel
// is a scan over DATA.ideas. Award reuses /api/uat-award -- the one path that
// writes the live meritdb, and the only place `awarded` is ever set.
let REVQ = {showAll:false};

// Every unpaid UAT credit, joined to whatever that player reported on the item.
function reviewRows(){
  const out=[];
  DATA.ideas.forEach(it=>{
    (it.uat_credits||[]).forEach(c=>{
      const who = (typeof c==='string' ? c : (c.player||'')).trim();
      if (!who || (typeof c!=='string' && c.awarded)) return;
      const steps = (it.manual_steps||[]).filter(s=>
        s && typeof s==='object' && s.kind==='uat'
        && (s.tested_by||'').trim().toLowerCase() === who.toLowerCase());
      // A credit somebody typed in by hand has no report behind it. That is
      // legitimate (the admin crediting a player who told them in Discord), so
      // it is shown -- just marked, because there is nothing here to review.
      if (!steps.length && !REVQ.showAll) return;
      out.push({idea:it, player:who, steps});
    });
  });
  const when = r => r.steps.map(s=>s.tested_on||'').sort().pop() || '';
  out.sort((a,b)=> String(when(b)).localeCompare(String(when(a)))
                || String(a.idea.title||'').localeCompare(String(b.idea.title||'')));
  return out;
}

function reviewRowHTML(r){
  const reports = r.steps.map(s=>`
    <div class="qtext">${esc(s.step||'')}
      <span class="ho-badge${s.status==='failed'?' bad':''}">${
        esc(QSTEP_LABEL[s.status]||s.status||'')}</span>
      ${(s.result||'').trim()?`<div class="qresult">${esc(s.result)}</div>`:''}
    </div>`).join('')
    || '<div class="qtext"><span class="small">No recorded result — this credit '
       + 'was added by hand.</span></div>';
  const when = r.steps.map(s=>s.tested_on||'').sort().pop() || '';
  return `<div class="qrow">
    <div class="qmeta">
      <button class="qtitle" data-goto="${esc(r.idea.id)}">${esc(r.idea.title||r.idea.id)}</button>
      <span class="qsub"><b>${esc(r.player)}</b>${when?' · '+esc(when):''}</span>
    </div>
    ${reports}
    <div class="qctl qclaim">
      <button class="rv_award" data-id="${esc(r.idea.id)}"
              data-p="${esc(r.player)}"
              title="Credit 1 merit in the live merit database">Award +1</button>
      <button class="rv_drop" data-id="${esc(r.idea.id)}" data-p="${esc(r.player)}"
              title="Remove the credit without paying it">Dismiss</button>
      <button class="q_open" data-goto="${esc(r.idea.id)}">Open item</button>
    </div>
  </div>`;
}

function renderReview(){
  const box=$('#rv_results'); if(!box) return;
  const rows = reviewRows();
  $('#rv_count').textContent = rows.length
    ? rows.length + (rows.length===1?' credit':' credits') + ' waiting to be paid'
    : 'Nothing waiting.';
  box.innerHTML = rows.length
    ? rows.map(reviewRowHTML).join('')
    : '<p class="small">No unpaid UAT credits. When a tester records a result, '
      + 'it appears here.</p>';
}

function openReview(){
  REVQ = {showAll:false};
  modalHTML(`<h2>UAT Review</h2>
    <p class="small">Every UAT credit that has not been paid, with what the
      tester actually reported. <b>Award +1</b> writes the live merit database;
      <b>Dismiss</b> removes the credit without paying it. Neither touches the
      item's status.</p>
    <div class="qbar">
      <label class="chk"><input type="checkbox" id="rv_all">
        also show credits with no recorded result</label>
      <span class="spacer"></span>
      <span class="pf-meta" id="rv_count"></span>
    </div>
    <div id="rv_results"></div>
    <div class="bar"><span class="spacer"></span><button id="rv_close">Close</button></div>`);
  $('#modalbox').classList.add('wide');
  $('#rv_close').onclick=()=>{ $('#modalbox').classList.remove('wide'); closeModal(); };
  $('#rv_all').onchange=e=>{ REVQ.showAll=e.target.checked; renderReview(); };
  $('#rv_results').addEventListener('click', async e=>{
    const a=e.target.closest('.rv_award'), d=e.target.closest('.rv_drop');
    if (a){ await reviewAward(a.dataset.id, a.dataset.p); return; }
    if (d){ await reviewDismiss(d.dataset.id, d.dataset.p); return; }
    const g=e.target.closest('[data-goto]'); if(!g) return;
    $('#modalbox').classList.remove('wide'); closeModal();
    guard(()=>{ if (view!=='list') setView('list'); selectById(g.dataset.goto, -1); });
  });
  renderReview();
}

// Pay one credit. Same endpoint as the form's Award +1 button — meritdb first,
// and the roadmap only records it if that write succeeded (_uat_write).
async function reviewAward(id, player){
  const it = DATA.ideas.find(x=>x.id===id); if(!it) return;
  if (!confirm('Grant 1 merit point to ' + player + ' for validating "'
    + (it.title||id) + '"?\n\nThe game DB is written now; the roadmap only '
    + 'records it if that write succeeds.')) return;
  const ok = await commit('/api/uat-award', false,
                          {stay:true, extra:{idea_id:id, player}});
  if (ok !== false) renderReview();
}

// Drop an unpaid credit. A plain document save — the same thing the form's ×
// button does — so it goes through /api/save and its permission check.
async function reviewDismiss(id, player){
  const it = DATA.ideas.find(x=>x.id===id); if(!it) return;
  if (!confirm('Remove ' + player + "'s unpaid UAT credit on \""
    + (it.title||id) + '"?\n\nTheir recorded result stays on the step; only '
    + 'the credit goes.')) return;
  it.uat_credits = (it.uat_credits||[]).filter(c=>
    (typeof c==='string' ? c : (c.player||'')).trim().toLowerCase()
      !== player.toLowerCase());
  const ok = await commit('/api/save', false, {stay:true});
  if (ok !== false) renderReview();
}

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

// Epics: umbrella items that ideas hang off via `epic:`. On the published page
// and the in-game sign an epic replaces its children with a single "x/y
// complete" card, so a big multi-part project doesn't spam either surface.
function openEpics(){
  const gopts = g => DATA.vocab.groups.map(x=>
    `<option value="${esc(x.id)}"${x.id===g?' selected':''}>${esc(dispAmp(x.title))}</option>`).join('');
  const rows = (DATA.vocab.epics||[]).map((e,i)=>`
    <div class="mrow" data-i="${i}" style="flex-wrap:wrap">
      <span class="gid" title="${esc(e.id)}">${esc(e.id)}</span>
      <input class="et" value="${esc(dispAmp(e.title||''))}">
      <select class="eg" style="flex:0 0 190px">${gopts(e.group)}</select>
      <span class="use">${DATA.ideas.filter(it=>it.epic===e.id).length}</span>
      <button class="linkbtn edel">remove</button>
      <input class="en" style="flex:1 0 100%" placeholder="public blurb (optional)"
             value="${esc(e.notes||'')}">
    </div>`).join('');
  modalHTML(`<h2>Manage epics</h2>
    <p class="small">An epic groups many ideas into one published card
      (&ldquo;7 / 12 complete&rdquo; with a tick per child, dated by the most recent
      shipped child). The <b>id</b> is the stable key ideas reference; the number is
      how many ideas belong to it. Epics earn no merit &mdash; the child ideas still do.</p>
    <div class="mlist" id="erows">${rows||'<div class="mrow"><span class="use">No epics yet.</span></div>'}</div>
    <h3 style="font-size:13px;margin:12px 0 4px;">Add an epic</h3>
    <div class="mrow">
      <input id="ne_id" class="gid" style="flex:0 0 150px;" placeholder="id (lowercase-hyphen)">
      <input id="ne_title" placeholder="Title (shown on the page)">
      <select id="ne_group" style="flex:0 0 190px">${gopts(DATA.vocab.groups[0]&&DATA.vocab.groups[0].id)}</select>
      <button id="ne_add">Add</button>
    </div>
    <div class="hint" id="e_hint"></div>
    <div class="bar"><button class="primary" id="e_save">Save changes</button>
      <span class="spacer"></span><button id="e_close">Close</button></div>`);
  $('#ne_add').onclick=()=>{
    const id=$('#ne_id').value.trim(), title=$('#ne_title').value.trim();
    if(!/^[a-z0-9-]+$/.test(id)){ $('#e_hint').textContent='id must be lowercase letters/digits/hyphens'; return; }
    if((DATA.vocab.epics||[]).some(e=>e.id===id)){ $('#e_hint').textContent='that id already exists'; return; }
    if(!title){ $('#e_hint').textContent='give the epic a title'; return; }
    DATA.vocab.epics=(DATA.vocab.epics||[]).concat(
      [{id, title:escAmp(title), group:$('#ne_group').value, notes:''}]);
    openEpics();
  };
  document.querySelectorAll('#erows .edel').forEach(b=>b.onclick=()=>{
    const e=DATA.vocab.epics[+b.closest('.mrow').dataset.i];
    const n=DATA.ideas.filter(it=>it.epic===e.id).length;
    if(n>0){ $('#e_hint').textContent=`“${e.id}” is used by ${n} idea(s) — clear their Epic field first`; return; }
    DATA.vocab.epics=DATA.vocab.epics.filter(x=>x.id!==e.id); openEpics();
  });
  $('#e_save').onclick=()=>{
    document.querySelectorAll('#erows .mrow[data-i]').forEach(row=>{
      const e=DATA.vocab.epics[+row.dataset.i];
      e.title=escAmp(row.querySelector('.et').value.trim());
      e.group=row.querySelector('.eg').value;
      e.notes=row.querySelector('.en').value.trim();
    });
    commit('/api/save'); closeModal();
  };
  $('#e_close').onclick=closeModal;
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
  api('/api/pending').then(r=>r.json()).then(d=>{
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

// ---- Recent changes: the audit log, read-only ---------------------------
// Deliberately has no controls beyond the day window: this is the record of
// what everyone did, and the one thing it must never offer is a way to change
// it. `audit_view` is an admin+DM capability today; a future `player` role is
// sketched without it, which is why this is a capability and not a role test.
let AUDIT_DAYS_VIEW = 7;

// The audit action verbs are terse by design (they are also what the CLI
// prints). Give them a human label here rather than renaming them in the DB,
// where old rows would then read differently from new ones.
const AUDIT_LABELS = {
  'login.ok':'Signed in', 'login.fail':'Failed sign-in',
  'login.throttled':'Sign-in throttled', 'logout':'Signed out',
  'denied.route':'Denied (route)', 'denied.field':'Denied (field)',
  'roadmap.save':'Saved roadmap', 'roadmap.step':'Ticked a step',
  'roadmap.regenerate':'Regenerated HTML', 'roadmap.publish':'Published',
  'merit.award':'Awarded merit', 'merit.revoke':'Revoked merit',
  'merit.uat_award':'Awarded UAT credit', 'merit.uat_revoke':'Revoked UAT credit',
  'llm.action':'LLM change review', 'palette.refresh':'Refreshed palette map',
  'user.add':'Added user', 'user.passwd':'Changed a password',
  'user.role':'Changed a role', 'user.disable':'Disabled user',
  'user.enable':'Enabled user', 'user.delete':'Deleted user',
  'user.logout':'Revoked sessions'
};
function auditLabel(a){ return AUDIT_LABELS[a] || a; }
// Anything that was refused, or that failed, is worth spotting at a glance.
function auditClass(a){
  if (a.startsWith('denied.') || a === 'login.fail' || a === 'login.throttled')
    return 'bad';
  return '';
}
function auditWhen(ts){
  const d = new Date((ts||0)*1000);
  if (isNaN(d)) return '';
  const p = n => String(n).padStart(2,'0');
  return `${d.getFullYear()}-${p(d.getMonth()+1)}-${p(d.getDate())} `
       + `${p(d.getHours())}:${p(d.getMinutes())}`;
}

// The Detail cell. For a write that recorded a per-field diff, each idea id
// becomes a button that expands the before/after in place; everything else --
// sign-ins, denials, and any row written before diffs existed -- keeps the
// plain escaped detail string it has always shown. The chips come from
// `diff_ids`, not from parsing `detail`: that text is capped at 8 ids with a
// "(+N more)" tail, so it is lossy and the map is not.
function auditDetailHTML(r){
  const marks = r.diff_ids || {};
  const ids = Object.keys(marks).filter(k=>k);
  if(!ids.length) return esc(r.detail||'');
  ids.sort();
  return ids.map(id=>`<button class="linkbtn idchip" data-audit-diff="${esc(String(r.id))}"
      data-idea="${esc(id)}">${esc(id)} <span class="n">(${marks[id]})</span></button>`).join('');
}

// Word-level highlight for the long text fields (notes, impl_notes), where the
// change is usually a handful of words inside a paragraph and showing two full
// paragraphs side by side tells you nothing. Plain LCS over whitespace tokens.
function wordDiff(a, b){
  const A=String(a).split(/(\s+)/), B=String(b).split(/(\s+)/);
  const n=A.length, m=B.length;
  // Guard the O(n*m) table: past this the two texts share nothing useful anyway.
  if(n*m > 250000) return [esc(a), esc(b)];
  const L=Array.from({length:n+1},()=>new Uint32Array(m+1));
  for(let i=n-1;i>=0;i--) for(let j=m-1;j>=0;j--)
    L[i][j] = A[i]===B[j] ? L[i+1][j+1]+1 : Math.max(L[i+1][j], L[i][j+1]);
  let i=0,j=0,left='',right='';
  const del=t=>t.trim()?`<mark class="d-del">${esc(t)}</mark>`:esc(t);
  const add=t=>t.trim()?`<mark class="d-add">${esc(t)}</mark>`:esc(t);
  while(i<n && j<m){
    if(A[i]===B[j]){ left+=esc(A[i]); right+=esc(B[j]); i++; j++; }
    else if(L[i+1][j] >= L[i][j+1]){ left+=del(A[i]); i++; }
    else { right+=add(B[j]); j++; }
  }
  while(i<n){ left+=del(A[i]); i++; }
  while(j<m){ right+=add(B[j]); j++; }
  return [left, right];
}

// A stored side: JSON-encoded, or null when the field was simply not there.
function auditVal(v){
  if(v===null || v===undefined) return null;
  try { const o=JSON.parse(v); return typeof o==='string' ? o : JSON.stringify(o,null,1); }
  catch(e){ return String(v); }
}
const AUDIT_KIND_NOTE = { added:'new item', removed:'item deleted' };

function auditDiffHTML(d){
  if(!d.ok) return `<p class="hint">Could not read the change detail:
      ${esc(d.reason||'unknown error')}</p>`;
  if(!d.count) return `<p class="small">No field changes were recorded for this
      entry. Diffs are kept for ${d.keep_days} days, and only exist for writes
      made after this feature shipped.</p>`;
  const body = d.rows.map(r=>{
    if(r.field==='_truncated')
      return `<tr><td class="f">—</td><td colspan="2" class="hint">${esc(auditVal(r.after)||'')}</td></tr>`;
    let a=auditVal(r.before), b=auditVal(r.after);
    let ah, bh;
    if(a!==null && b!==null && (a.length>40 || b.length>40)) [ah,bh]=wordDiff(a,b);
    else { ah = a===null?'':esc(a); bh = b===null?'':esc(b); }
    const before = a===null ? '<span class="muted">(not set)</span>'
                            : `<div class="lc-before">${ah}</div>`;
    const after  = b===null ? '<span class="muted">(removed)</span>'
                            : `<div class="lc-after">${bh}</div>`;
    const note = AUDIT_KIND_NOTE[r.kind] ? ` <span class="muted">(${r.kind})</span>` : '';
    return `<tr><td class="f">${esc(r.field)}${note}</td>
        <td class="v">${before}</td><td class="v">${after}</td></tr>`;
  }).join('');
  return `<table class="au-fields">
      <tr><th>Field</th><th>Before</th><th>After</th></tr>${body}</table>`;
}

// Delegated so it survives the table being re-rendered by the day buttons.
function wireAuditDiff(){
  const tbl = $('#au_table'); if(!tbl) return;
  tbl.addEventListener('click', e=>{
    const btn = e.target.closest('[data-audit-diff]'); if(!btn) return;
    const row = btn.closest('tr');
    const open = row.nextElementSibling;
    if(open && open.classList.contains('au-diff')
       && open.dataset.idea === btn.dataset.idea){
      open.remove(); btn.classList.remove('open'); return;
    }
    if(open && open.classList.contains('au-diff')) open.remove();
    row.parentNode.querySelectorAll('.idchip.open').forEach(b=>b.classList.remove('open'));
    btn.classList.add('open');
    const tr = document.createElement('tr');
    tr.className = 'au-diff';
    tr.dataset.idea = btn.dataset.idea;
    tr.innerHTML = `<td colspan="6"><p class="small">Loading changes to
        <code>${esc(btn.dataset.idea)}</code>…</p></td>`;
    row.after(tr);
    api('/api/audit/diff?entry='+encodeURIComponent(btn.dataset.auditDiff)
        +'&idea='+encodeURIComponent(btn.dataset.idea))
      .then(r=>r.json()).then(d=>{
        tr.innerHTML = `<td colspan="6"><p class="small">Changes to
          <code>${esc(btn.dataset.idea)}</code> in this write:</p>
          ${auditDiffHTML(d)}</td>`;
      }).catch(err=>{
        tr.innerHTML = `<td colspan="6"><p class="hint">Could not load:
          ${esc(String(err))}</p></td>`;
      });
  });
}

function openAudit(days){
  AUDIT_DAYS_VIEW = days || AUDIT_DAYS_VIEW;
  modalHTML(`<h2>Recent changes</h2><p class="small">Loading the audit log…</p>`);
  $('#modalbox').classList.add('wide');
  api('/api/audit?days='+encodeURIComponent(AUDIT_DAYS_VIEW))
    .then(r=>r.json()).then(d=>{
    const close = `<div class="bar"><span class="spacer"></span>
      <button id="au_close">Close</button></div>`;
    if(!d.available){
      modalHTML(`<h2>Recent changes</h2>
        <p class="hint">Could not read the audit log: ${esc(d.reason||'unknown error')}</p>
        ${close}`);
      $('#au_close').onclick=closeAudit; return;
    }
    const rows=(d.rows||[]).map(r=>`<tr class="${auditClass(r.action||'')}">
        <td class="muted nw">${esc(auditWhen(r.ts))}</td>
        <td>${esc(r.username||'—')}</td>
        <td class="muted">${esc(r.role||'')}</td>
        <td class="nw">${esc(auditLabel(r.action||''))}</td>
        <td class="det">${auditDetailHTML(r)}</td>
        <td class="muted nw">${esc(r.ip||'')}</td>
      </tr>`).join('');
    const body = d.count
      ? `<table class="txns audit" id="au_table">
          <tr><th>When</th><th>Who</th><th>Role</th><th>What</th>
              <th>Detail</th><th>From</th></tr>
          ${rows}</table>`
      : `<p class="small">Nothing recorded in the last ${d.days} days.</p>`;
    const more = d.truncated
      ? `<p class="hint">Showing the newest ${d.limit} entries only — there are
           more in this window. <code>python3 bin/roadmap-users.py audit</code>
           reads the full log.</p>` : '';
    modalHTML(`<h2>Recent changes</h2>
      <p class="small">The last ${d.days} days of the editor's audit log, newest
        first — every sign-in, save, publish and merit payment, by whoever made
        it. Read-only. Click an idea id in <b>Detail</b> to see exactly which
        fields that write changed, and what they were before.</p>
      ${body}${more}
      <div class="bar">
        <button id="au_7" class="linkbtn">7 days</button>
        <button id="au_30" class="linkbtn">30 days</button>
        <span class="spacer"></span>
        <button id="au_close">Close</button></div>`);
    wireAuditDiff();
    $('#au_7').onclick=()=>openAudit(7);
    $('#au_30').onclick=()=>openAudit(30);
    $('#au_close').onclick=closeAudit;
  }).catch(e=>{
    modalHTML(`<h2>Recent changes</h2>
      <p class="hint">Could not load: ${esc(String(e))}</p>
      <div class="bar"><span class="spacer"></span><button id="au_close">Close</button></div>`);
    $('#au_close').onclick=closeAudit;
  });
}
function closeAudit(){ $('#modalbox').classList.remove('wide'); closeModal(); }

['f_fstatus','f_ftype','f_fplayer','f_fgroup','f_fepic','f_fhidden','f_sort']
  .forEach(id=>$('#'+id).onchange=render);
$('#f_showawarded').onchange=render;
// Regenerate/Publish act on the whole file, so they live in the left pane and
// work from the Board view too (commit() folds the open form in when in List).
$('#regen').onclick = ()=>commit('/api/regenerate');
$('#publish').onclick = ()=>{
  if(!confirm('Regenerate, publish the roadmap into the local docs/ AND the LIVE public wiki, sync the local in-game Recent Updates DB, commit & git push both repos?')) return;
  commit('/api/publish');
};
$('#mepics').onclick=openEpics;
$('#mgroups').onclick=openGroups;
$('#mplayers').onclick=openPlayers;
$('#mpending').onclick=openPending;
$('#mpalette').onclick=openPalette;
$('#mtoolq').onclick=()=>openQueue('toolset');
$('#muatq').onclick=()=>openQueue('uat');
$('#muatr').onclick=openReview;
$('#mchanges').onclick=openChanges;
$('#maudit').onclick=openAudit;
$('#logout').onclick=async ()=>{
  if (!confirm('Sign out of the roadmap editor?')) return;
  try { await fetch('/api/logout', {method:'POST',
        headers:{'Content-Type':'application/json'}, body:'{}'}); } catch(e){}
  location.href = '/login';
};
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
    const d=await (await api('/api/version')).json();
    if (d.version && baseVersion && d.version!==baseVersion){
      const b=$('#banner');
      if (!b.querySelector('button')){   // don't stomp an active conflict banner
        banner('warn','roadmap.yaml changed on disk (external edit) — Reload '
          +'to see it. Your edits are safe: a Save merges around changes to '
          +'other items, and only warns if the same item was edited on both sides.');
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
    ap.add_argument("--host", default="127.0.0.1",
                    help="bind address (default 127.0.0.1; the Cloudflare Tunnel "
                         "reaches it there, and public access is meant to arrive "
                         "through the tunnel rather than an open port)")
    ap.add_argument("--serve", action="store_true",
                    help="serve without opening a browser (used by the systemd unit)")
    args = ap.parse_args()

    httpd = ThreadingHTTPServer((args.host, args.port), Handler)
    url = f"http://localhost:{args.port}/"
    print(f"Roadmap editor serving on {args.host}:{args.port}  (editing {YAML_PATH})")
    try:
        conn = AUTH.connect()
        n = AUTH.user_count(conn)
        print(f"  auth: {n} account(s) in {AUTH.db_path()}")
        if n == 0:
            # Not a fatal condition — the service must still come up so the
            # login page can say what to do — but it is the whole difference
            # between "working" and "nobody can get in", so shout it.
            print("  " + AUTH.bootstrap_hint().replace("\n", "\n  "))
    except Exception as exc:  # noqa: BLE001
        print(f"  [warn] auth database unavailable: {exc}", file=sys.stderr)
    if args.host not in ("127.0.0.1", "localhost", "::1"):
        try:
            host = socket.gethostname()
            ip = socket.gethostbyname(host)
            print(f"  LAN access: http://{host}:{args.port}/  or  http://{ip}:{args.port}/")
        except Exception:
            pass
        print("  (bound beyond loopback — every request still needs a login, but "
              "the session cookie is sent in the clear over plain HTTP)")
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
