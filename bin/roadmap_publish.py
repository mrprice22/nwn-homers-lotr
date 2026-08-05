#!/usr/bin/env python3
"""Write roadmap.yaml's shipped work into the in-game Recent Updates sign DB.

The Well of Eru sign (placeable tag `recent_updates`, conversation `ru_sign`,
read by `unpacked/ru_db.nss`) browses the campaign SQLite DB **roadmapdb**. This
module owns the writing half; in-game it is read-only.

Two buckets, and the split is the point of the whole thing:

    shipped   validated work — the 10 newest shipped ideas that have no open
              `uat` manual_step left. Epics collapse to one "x/y complete" card,
              exactly as they do on the public roadmap page.
    testing   shipped-but-unvalidated work — EVERY idea that still has an open
              `uat` step, no cap, no epic collapse (a tester needs the single
              item, not the project card). Its notes carry the open UAT steps
              and who can run them, so a player can actually help.

Lives outside bin/roadmap-editor.py so the nightly refresh can call it without
starting a web server — before this split the sign could only be updated by a
human clicking "Publish to Wiki & DB" in the browser, and it silently went stale
whenever an agent shipped something. bin/publish-roadmap-db.py is the CLI;
the editor imports these same functions for its Publish button.

The DB is NOT git-tracked (it lives under NWN_HOME_DIR); the live server picks
up changes on next read, with no restart.
"""
from __future__ import annotations

import html
import importlib.util
import os
import re
import sqlite3
from pathlib import Path

REPO = Path(__file__).resolve().parent.parent
YAML_PATH = REPO / "roadmap.yaml"
GEN_PATH = REPO / "bin" / "gen-roadmap.py"
SERVER_ENV = REPO / "server.env"


def load_gen():
    """Import gen-roadmap.py (hyphenated name) for STATUS + the step helpers."""
    spec = importlib.util.spec_from_file_location("gen_roadmap", GEN_PATH)
    mod = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(mod)
    return mod


GEN = load_gen()

# An idea is on the sign once it has shipped. `manual` counts: the code is live,
# it is the admin's own finishing work that is outstanding — and if that work is
# a UAT step, the bucket split below puts it in front of the players who can help.
SHIPPED_STATUSES = ("implemented", "awarded", "manual")
TYPE_PREFIX = {
    "Defect":      "Bug fixed: ",
    "Enhancement": "New feature: ",
    "Exploit":     "Exploit closed: ",
}
DEFAULT_PREFIX = "Update: "
TESTING_PREFIX = "Needs testing: "
BUCKET_SHIPPED = "shipped"
BUCKET_TESTING = "testing"
SHIPPED_LIMIT = 10          # the sign has always shown the 10 newest
_TAG_RE = re.compile(r"<[^>]+>")
_BLANKS_RE = re.compile(r"\n[ \t]*\n[ \t]*\n+")

SCHEMA = ("CREATE TABLE IF NOT EXISTS recent_updates ("
          "bucket TEXT NOT NULL DEFAULT 'shipped', "
          "rank INTEGER NOT NULL, title TEXT, prefix TEXT, "
          "group_label TEXT, player TEXT, date TEXT, notes TEXT, "
          "PRIMARY KEY (bucket, rank))")


def nwn_home_dir() -> Path:
    """This repo's NWN_HOME_DIR — i.e. THIS season's campaign DB directory.

    Reading server.env is what keeps a publish inside the right season. The old
    code took $NWN_HOME_DIR or fell back to the literal unnumbered
    "~/.local/share/Neverwinter Nights", and the systemd units set no
    environment — so after the season 1 -> 2 cutover the editor ran from the
    season-2 repo and published roadmapdb into SEASON 1's database dir, leaving
    season 2's Recent Updates sign blank.

    Precedence: explicit env override, then server.env, then the legacy path.
    """
    env = os.environ.get("NWN_HOME_DIR")
    if env:
        return Path(os.path.expandvars(env))
    try:
        for ln in SERVER_ENV.read_text(encoding="utf-8").splitlines():
            m = re.match(r"\s*(?:export\s+)?NWN_HOME_DIR\s*=\s*(.+?)\s*$", ln)
            if m:
                val = m.group(1).strip().strip('"').strip("'")
                # server.env writes "$HOME/.local/share/..."
                return Path(os.path.expandvars(val))
    except OSError:
        pass
    return Path(os.path.expanduser("~")) / ".local/share/Neverwinter Nights"


def recent_db_path() -> Path:
    """Filesystem path to the live roadmapdb campaign database."""
    return nwn_home_dir() / "database" / "roadmapdb.sqlite3"


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


def player_label(idea: dict) -> str:
    p = idea.get("player") or ""
    return "Community" if p == "community" else p


def is_shipped(idea: dict) -> bool:
    return idea.get("status") in SHIPPED_STATUSES


def testing_block(idea: dict) -> str:
    """The 'what still needs testing' tail appended to a testing-bucket entry.

    This is the half a player can act on: the open UAT steps in plain text, each
    tagged with the character it takes to run it.
    """
    lines = []
    for step in GEN.open_uat_steps(idea):
        who = (step.get("tester") or "").strip()
        text = html_to_plain(str(step.get("step", "")))
        text = " ".join(text.split())
        lines.append(f"• ({who}) {text}" if who else f"• {text}")
    if not lines:
        return ""
    return "What still needs testing:\n" + "\n".join(lines)


def _epic_row(epic: dict, children: list, glabel: dict) -> tuple | None:
    """One rolled-up sign entry for an epic, or None if nothing shipped yet.

    Mirrors the wiki card: an "x/y complete" headline plus an ASCII checklist of
    the children (the sign renders plain text through SetCustomToken).
    """
    done = [c for c in children if is_shipped(c)]
    if not done:
        return None
    players: list[str] = []
    for c in children:
        p = player_label(c)
        if p and p not in players:
            players.append(p)
    checklist = "\n".join(
        ("[x] " if is_shipped(c) else "[ ] ") + (c.get("title") or "")
        for c in children)
    blurb = html_to_plain(epic.get("notes") or "")
    return (
        f'{epic.get("title") or epic["id"]} '
        f'({len(done)}/{len(children)} complete)',
        "Project: ",
        glabel.get(epic.get("group"), epic.get("group") or ""),
        ", ".join(players),
        max((c.get("date") or "") for c in done),
        (blurb + "\n\n" if blurb else "") + checklist,
    )


def build_rows(ideas: list, groups: list | None,
               epics: list | None = None) -> dict[str, list[tuple]]:
    """Both buckets' rows, each already sorted newest-first.

    Returns {bucket: [(title, prefix, group_label, player, date, notes), ...]}.
    `hidden` ideas never reach the sign at all.
    """
    GEN.resolve_dates(ideas)  # explicit date wins; else derived from commit
    glabel = {g["id"]: html.unescape(g.get("title", g["id"]))
              for g in (groups or [])}
    by_epic = {e["id"]: e for e in (epics or [])}
    visible = [i for i in ideas if not i.get("hidden") and not i.get("dupe_of")]

    # An idea with an open UAT step goes to the testing bucket whether or not it
    # belongs to an epic: the epic card is a progress summary, no use to someone
    # trying to reproduce a specific check.
    testing = [i for i in visible if is_shipped(i) and GEN.open_uat_steps(i)]
    testing_ids = {id(i) for i in testing}

    kids: dict[str, list] = {}
    loose = []
    for idea in visible:
        if id(idea) in testing_ids:
            continue
        eid = idea.get("epic")
        if eid in by_epic:
            kids.setdefault(eid, []).append(idea)
        elif is_shipped(idea):
            loose.append(idea)

    shipped_rows: list[tuple] = []
    for idea in loose:
        shipped_rows.append((
            idea.get("title") or "",
            TYPE_PREFIX.get(idea.get("type"), DEFAULT_PREFIX),
            glabel.get(idea.get("group"), idea.get("group") or ""),
            player_label(idea),
            idea.get("date") or "",
            html_to_plain(idea.get("notes") or ""),
        ))
    for eid, children in kids.items():
        row = _epic_row(by_epic[eid], children, glabel)
        if row:
            shipped_rows.append(row)
    shipped_rows.sort(key=lambda e: (e[4], e[0]), reverse=True)

    testing_rows: list[tuple] = []
    for idea in testing:
        notes = html_to_plain(idea.get("notes") or "")
        tail = testing_block(idea)
        testing_rows.append((
            idea.get("title") or "",
            TESTING_PREFIX,
            glabel.get(idea.get("group"), idea.get("group") or ""),
            player_label(idea),
            idea.get("date") or "",
            (notes + "\n\n" + tail) if notes else tail,
        ))
    testing_rows.sort(key=lambda e: (e[4], e[0]), reverse=True)

    return {BUCKET_SHIPPED: shipped_rows[:SHIPPED_LIMIT],
            BUCKET_TESTING: testing_rows}


def _ensure_schema(con) -> None:
    """Create the table, migrating the pre-bucket single-list schema in place.

    The old table had `rank INTEGER PRIMARY KEY` and no bucket column, so
    ru_db.nss's `WHERE bucket=@b` would find nothing against it. Every publish
    rewrites all rows anyway, so dropping is lossless.
    """
    cols = [r[1] for r in con.execute("PRAGMA table_info(recent_updates)")]
    if cols and "bucket" not in cols:
        con.execute("DROP TABLE recent_updates")
    con.execute(SCHEMA)


def sync_recent_updates_db(ideas: list, groups: list | None,
                           epics: list | None = None) -> tuple[bool, str]:
    """Refill roadmapdb.recent_updates from roadmap.yaml. Returns (ok, message)."""
    buckets = build_rows(ideas, groups, epics)
    rows = [(bucket, rank) + entry
            for bucket, entries in buckets.items()
            for rank, entry in enumerate(entries)]

    db = recent_db_path()
    db.parent.mkdir(parents=True, exist_ok=True)
    con = sqlite3.connect(str(db))
    try:
        _ensure_schema(con)
        con.execute("DELETE FROM recent_updates")
        con.executemany(
            "INSERT INTO recent_updates"
            "(bucket,rank,title,prefix,group_label,player,date,notes)"
            " VALUES(?,?,?,?,?,?,?,?)", rows)
        con.commit()
    finally:
        con.close()
    return True, (f"synced {len(buckets[BUCKET_SHIPPED])} recent + "
                  f"{len(buckets[BUCKET_TESTING])} in-testing update(s) "
                  f"to {db.name}.")
