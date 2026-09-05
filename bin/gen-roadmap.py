#!/usr/bin/env python3
"""Generate docs.manual/Roadmap.html from roadmap.yaml.

The roadmap page is the public, player-facing view of the development backlog:
what has shipped (with merit credited to the player who suggested it), and what
is in progress / up next, grouped by feature theme. It doubles as the builder's
working backlog and a duplicate-idea guard.

Usage:
    python3 bin/gen-roadmap.py            # writes docs.manual/Roadmap.html
    python3 bin/gen-roadmap.py --check    # validate only, write nothing

The output is a standalone <body><main> HTML doc; the wiki build
(nwn-manager wiki -> render_manual_pages) strips the head/body and injects the
shared site header, footer and nav. Dropping this file in docs.manual/ is enough
for it to appear in the "Documents" nav dropdown.
"""
from __future__ import annotations

import argparse
import json
import re
import subprocess
import sys
from datetime import datetime
from pathlib import Path

import yaml

# libyaml's CSafeLoader parses roadmap.yaml ~12x faster than the pure-Python
# SafeLoader (0.17 s vs 2.0 s on an 800 KB file). Fall back when unavailable.
try:
    from yaml import CSafeLoader as _YamlLoader
except ImportError:                                  # pragma: no cover
    from yaml import SafeLoader as _YamlLoader

sys.path.insert(0, str(Path(__file__).resolve().parent))
from roadmap_sanitize import sanitize_notes  # noqa: E402

REPO = Path(__file__).resolve().parent.parent
YAML_PATH = REPO / "roadmap.yaml"
OUT_PATH = REPO / "docs.manual" / "Roadmap.html"
# Machine-readable credit sidecar for the wiki build (see write_credits()).
CREDITS_PATH = REPO / "roadmap-credits.json"
SERVER_ENV = REPO / "server.env"


def season_role() -> str:
    """This repo's SEASON_ROLE (live | test | dev | archive), "" if unknown.

    Same one-line parse as bin/roadmap_publish.py's nwn_home_dir() and
    bin/promote-to-prod: last assignment wins, quotes and trailing comment
    stripped. A repo with no server.env (fresh clone, CI) returns "".
    """
    try:
        text = SERVER_ENV.read_text(encoding="utf-8")
    except OSError:
        return ""
    val = ""
    for ln in text.splitlines():
        m = re.match(r"\s*(?:export\s+)?SEASON_ROLE\s*=\s*(.+?)\s*$", ln)
        if m:
            val = m.group(1).strip()
    # A quoted value ends at its closing quote (server.env comments inline
    # after it); an unquoted one ends at the '#'.
    if val[:1] in ('"', "'"):
        end = val.find(val[0], 1)
        return val[1:end] if end != -1 else val[1:]
    return val.split("#", 1)[0].strip()

# Status -> (badge label, css modifier, which board it belongs to).
# board "shipped" = Recently Shipped timeline; "roadmap" = In Progress / Up Next.
STATUS = {
    "awarded":     {"label": "Shipped · Merit awarded", "cls": "shipped",  "board": "shipped", "rank": 0},
    "implemented": {"label": "Shipped · in testing",     "cls": "testing",  "board": "shipped", "rank": 1},
    "confirmed":   {"label": "In progress",                  "cls": "active",   "board": "roadmap", "rank": 0},
    "manual":      {"label": "Needs manual finishing",       "cls": "manual",   "board": "roadmap", "rank": 1},
    "design":      {"label": "Needs design input",           "cls": "design",   "board": "roadmap", "rank": 2},
    "wip":         {"label": "Up next",                      "cls": "queued",   "board": "roadmap", "rank": 3},
    "soon":        {"label": "Soon",                         "cls": "soon",     "board": "roadmap", "rank": 4},
    "later":       {"label": "Later",                        "cls": "later",    "board": "roadmap", "rank": 5},
    "planned":     {"label": "Under consideration",          "cls": "planned",  "board": "roadmap", "rank": 6},
    "unlikely":    {"label": "Not likely to implement",      "cls": "unlikely", "board": "roadmap", "rank": 7},
}

# Idea kind -> (badge label, css modifier). The merit value of a *shipped*
# (awarded) idea depends on its type: Defect=1, Enhancement=2, Exploit=3.
TYPES = {
    "Defect":      {"label": "Defect",      "cls": "defect"},
    "Enhancement": {"label": "Enhancement", "cls": "enhancement"},
    "Exploit":     {"label": "Exploit",     "cls": "exploit"},
}
MERIT_POINTS = {"Defect": 1, "Enhancement": 2, "Exploit": 3}

# The three lifecycle buckets the ten statuses collapse into, for the summary
# pivot on this page and for the per-player pivot the wiki builds from the
# credit sidecar. Both call pivot_column(), so a status can never land in one
# bucket here and a different one there.
PIVOT_COLUMNS = ("Backlog", "Shipped", "Not Likely")


def pivot_column(status: str) -> str:
    """Which pivot bucket a status belongs to."""
    if STATUS[status]["board"] == "shipped":
        return "Shipped"
    return "Not Likely" if status == "unlikely" else "Backlog"


# What kind of session a manual_step belongs to. This is what makes the backlog
# reportable: "show me everything I can do in this toolset sitting" vs "…in this
# game-client sitting". Absent means `admin` — the fallback bucket, not a claim
# that the step was triaged.
#   toolset  waypoint placement, palette/blueprint work, appearance, portrait,
#            voiceset, inventory icons — anything done in the NWN toolset
#   uat      in-game verification: log in, spawn it, confirm it reads right
#   admin    everything else (DB seeding, hygiene, out-of-band chores)
# There is deliberately NO `publish`/deploy kind. Repack, hak build, NWSync and
# restart are implied by every shipped item — the admin already knows work has
# to be deployed before it can be tested — so tracking them per item only added
# rows to click through. Removed 2026-08-26; put anything genuinely unusual
# about a deploy in `impl_notes`, not in a step.
STEP_KINDS = ("toolset", "uat", "admin")
DEFAULT_STEP_KIND = "admin"


def step_kind(step) -> str:
    """The reporting bucket a manual_step belongs to (legacy strings -> admin)."""
    if not isinstance(step, dict):
        return DEFAULT_STEP_KIND
    kind = step.get("kind")
    return kind if kind in STEP_KINDS else DEFAULT_STEP_KIND


def open_steps(idea: dict, kinds=None) -> list[dict]:
    """Unfinished manual_steps of an idea, optionally filtered to some kinds."""
    out = []
    for s in (idea.get("manual_steps") or []):
        if not isinstance(s, dict) or s.get("status") == "done":
            continue
        if kinds is None or step_kind(s) in kinds:
            out.append(s)
    return out


def open_uat_steps(idea: dict) -> list[dict]:
    """The predicate behind 'shipped but not validated'.

    A shipped idea with at least one of these is still in testing — that is what
    splits the in-game Recent Updates board and drives the UAT queue. Shared so
    the sign, the queue and the wiki can never disagree about what "validated"
    means.
    """
    return open_steps(idea, ("uat",))

# Every field an idea is allowed to carry. Anything else is preserved on save
# (bin/roadmap-editor.py round-trips it) but nothing renders it, so validate()
# warns — that is how a stray key like the old `fix:` gets noticed instead of
# quietly riding along forever. Keep in step with FIELD_ORDER in the editor,
# which orders these same names; the editor warns if the two ever disagree.
IDEA_FIELDS = {
    "id", "title", "group", "epic", "status", "hidden", "merit_awarded",
    "type", "player",
    "date", "commit", "notes", "notes_h", "impl_notes", "impl_notes_h",
    "dupe_of", "design_questions", "manual_steps", "uat_credits",
    # Set by nwnbot: which forum thread this idea is mirrored to. Nothing on
    # the public board renders it; it is the link the sync bot reads back.
    "discord",
    # Internal, append-only per-idea notes. Nothing here renders them: they are
    # how a tester (who has no `edit`) adds information to an item.
    "comments",
}

PLAYER_LABEL = {"community": "Community"}

_ENTITY_RE = re.compile(r"&(?:[a-zA-Z][a-zA-Z0-9]+|#\d+|#x[0-9a-fA-F]+);")


def amp(text: str) -> str:
    """Escape lone ampersands in trusted-but-plain author text, keep entities."""
    if text is None:
        return ""
    out, i = [], 0
    for m in _ENTITY_RE.finditer(text):
        out.append(text[i:m.start()].replace("&", "&amp;"))
        out.append(m.group(0))
        i = m.end()
    out.append(text[i:].replace("&", "&amp;"))
    return "".join(out)


def ordinal(day: int) -> str:
    if 10 <= day % 100 <= 20:
        suf = "th"
    else:
        suf = {1: "st", 2: "nd", 3: "rd"}.get(day % 10, "th")
    return f"{day}{suf}"


MONTHS = ["", "January", "February", "March", "April", "May", "June",
          "July", "August", "September", "October", "November", "December"]


def pretty_date(iso: str) -> str:
    """'2026-06-22' -> 'June 22nd, 2026'. Pass through anything unexpected."""
    m = re.match(r"^(\d{4})-(\d{2})-(\d{2})$", iso or "")
    if not m:
        return iso or ""
    y, mo, d = int(m[1]), int(m[2]), int(m[3])
    return f"{MONTHS[mo]} {ordinal(d)}, {y}"


def pretty_asof(value: str) -> str:
    """Render meta.as_of, which may be a bare date ('2026-06-22') or a date with
    a local time/zone the editor stamps ('2026-06-23 14:30 CDT'). The date part
    is prettified; any trailing time/zone is appended as 'at <rest>'."""
    value = (value or "").strip()
    if not value:
        return ""
    date_part, sep, rest = value.partition(" ")
    pretty = pretty_date(date_part)
    rest = rest.strip()
    return f"{pretty} at {rest}" if rest else pretty


def norm_title(t: str) -> str:
    return re.sub(r"[^a-z0-9]+", " ", t.lower()).strip()


def player_name(p: str | None) -> str:
    if not p:
        return ""
    return PLAYER_LABEL.get(p, p)


def validate(data: dict) -> list[str]:
    """Return a list of fatal errors; print warnings as we go."""
    errors: list[str] = []
    ideas = data.get("ideas", [])
    group_ids = {g["id"] for g in data.get("groups", [])}

    # Epics: a small block of umbrella items ideas can hang off. An epic is NOT
    # an idea — it carries no type, no player and no merit; it only collapses its
    # children into one card on the public page and the in-game sign.
    epic_ids: set[str] = set()
    for i, ep in enumerate(data.get("epics", []) or []):
        eid = ep.get("id")
        if not re.fullmatch(r"[a-z0-9-]+", eid or ""):
            errors.append(f"epic #{i}: id {eid!r} must be lowercase letters/digits/hyphens")
            continue
        if eid in epic_ids:
            errors.append(f"duplicate epic id '{eid}'")
        epic_ids.add(eid)
        if not str(ep.get("title", "")).strip():
            errors.append(f"epic '{eid}': needs a title")
        if ep.get("group") not in group_ids:
            errors.append(f"epic '{eid}': unknown group {ep.get('group')!r}")
        if ep.get("status") is not None and ep.get("status") not in STATUS:
            errors.append(f"epic '{eid}': unknown status {ep.get('status')!r}")

    seen: dict[str, int] = {}
    for i, idea in enumerate(ideas):
        iid = idea.get("id")
        if not iid:
            errors.append(f"idea #{i} is missing an id")
            continue
        if iid in seen:
            errors.append(f"duplicate id '{iid}' (also at index {seen[iid]})")
        seen[iid] = i
        # `title` is required (it IS the public description). It was never
        # checked here, so an untitled idea instead crashed the similar-title
        # scan below with a KeyError — which, in the editor, surfaced as a bare
        # "NetworkError" when the handler died mid-request. The editor's
        # pruneEmpty() drops an empty title entirely, so a brand-new idea saved
        # before it is filled in arrives with no `title` key at all.
        if not str(idea.get("title") or "").strip():
            errors.append(f"'{iid}': needs a title")
        if idea.get("status") not in STATUS:
            errors.append(f"'{iid}': unknown status {idea.get('status')!r}")
        if idea.get("group") not in group_ids:
            # Blank and wrong are different mistakes: blank is a new idea whose
            # picker was never touched (the editor starts it empty on purpose),
            # wrong is a group id that no longer exists. Saying "unknown group
            # ''" for the common case sent people hunting for a renamed group.
            if not str(idea.get("group") or "").strip():
                errors.append(f"'{iid}': needs a group")
            else:
                errors.append(f"'{iid}': unknown group {idea.get('group')!r}")
        if idea.get("type") is not None and idea.get("type") not in TYPES:
            errors.append(f"'{iid}': unknown type {idea.get('type')!r}")
        if idea.get("epic") and idea["epic"] not in epic_ids:
            errors.append(f"'{iid}': unknown epic {idea['epic']!r}")
        if idea.get("hidden") is not None and not isinstance(idea.get("hidden"), bool):
            errors.append(f"'{iid}': hidden must be true/false, got "
                          f"{idea.get('hidden')!r}")
        # manual_steps carry two reporting keys the queues filter on. A typo in
        # `kind` would silently drop the step out of both queues, so it is fatal.
        for step in (idea.get("manual_steps") or []):
            if not isinstance(step, dict):
                continue          # legacy bare string; upgraded on next save
            kind = step.get("kind")
            if kind is not None and kind not in STEP_KINDS:
                errors.append(f"'{iid}': unknown manual_step kind {kind!r} "
                              f"(expected one of {', '.join(STEP_KINDS)})")
            if step.get("tester") is not None \
                    and not isinstance(step["tester"], str):
                errors.append(f"'{iid}': manual_step tester must be text, got "
                              f"{step['tester']!r}")
        # Advisory, never fatal: the field is kept on save, but no renderer reads
        # it, so it is almost always a typo or a retired experiment.
        for key in idea:
            if key not in IDEA_FIELDS:
                print(f"  [warn] '{iid}': unrecognised field '{key}' (preserved, "
                      f"but nothing renders it)", file=sys.stderr)

    # dupe_of must point at a real id, and the target must not itself be a dupe.
    for idea in ideas:
        dof = idea.get("dupe_of")
        if dof and dof not in seen:
            errors.append(f"'{idea.get('id')}': dupe_of points to unknown id '{dof}'")

    # Similar-title warning among non-merged ideas (duplicate-idea guard).
    # Still every pair, but norm_title() (two regexes + a set build) is computed
    # once per idea instead of twice per *pair* — it was ~1.2 s of every save.
    # The same-group test is hoisted to the top of the loop for the same reason.
    # Pair order is unchanged, so the warning list is byte-identical.
    canon = [i for i in ideas if not i.get("dupe_of")]
    words = [set(norm_title(i.get("title") or "").split()) for i in canon]
    groups_of = [i["group"] for i in canon]
    for a in range(len(canon)):
        wa, ga = words[a], groups_of[a]
        if not wa:
            continue
        for b in range(a + 1, len(canon)):
            if groups_of[b] != ga:
                continue
            wb = words[b]
            if not wb:
                continue
            overlap = len(wa & wb) / max(1, min(len(wa), len(wb)))
            if overlap >= 0.7:
                print(f"  [warn] possible duplicate ideas (set dupe_of?): "
                      f"'{canon[a]['id']}' ~ '{canon[b]['id']}'", file=sys.stderr)
    return errors


def resolve_dates(ideas: list[dict]) -> None:
    """Fill `date` from `commit` via git when a shipped idea lacks an explicit date."""
    for idea in ideas:
        if idea.get("date") or not idea.get("commit"):
            continue
        try:
            out = subprocess.run(
                ["git", "log", "-1", "--format=%ad", "--date=short", idea["commit"]],
                cwd=REPO, capture_output=True, text=True, check=True,
            )
            idea["date"] = out.stdout.strip()
        except subprocess.CalledProcessError:
            print(f"  [warn] could not resolve commit {idea['commit']} "
                  f"for '{idea['id']}'", file=sys.stderr)


def merge_dupes(ideas: list[dict]) -> list[dict]:
    """Fold dupe_of ideas into their canonical idea, collecting requesters."""
    by_id = {i["id"]: i for i in ideas}
    for idea in ideas:
        idea.setdefault("_requesters", [])
        if idea.get("player"):
            idea["_requesters"].append(idea["player"])
    canon = []
    for idea in ideas:
        dof = idea.get("dupe_of")
        if dof:
            target = by_id[dof]
            for p in idea["_requesters"]:
                if p not in target["_requesters"]:
                    target["_requesters"].append(p)
        else:
            canon.append(idea)
    return canon


def publishable(ideas: list[dict]) -> list[dict]:
    """Drop `hidden` ideas — internal items that must never reach the public page.

    Dropped before merge_dupes() so a hidden row's title AND its submitter credit
    both stay off the page. A visible idea whose dupe_of target was hidden loses
    the link (it renders standalone) with a warning, rather than crashing.
    """
    kept = [i for i in ideas if not i.get("hidden")]
    live = {i.get("id") for i in kept}
    for idea in kept:
        dof = idea.get("dupe_of")
        if dof and dof not in live:
            print(f"  [warn] '{idea['id']}': dupe_of '{dof}' is hidden — "
                  f"rendering it as its own item", file=sys.stderr)
            idea.pop("dupe_of")
    return kept


def is_shipped(idea: dict) -> bool:
    return STATUS[idea["status"]]["board"] == "shipped"


def collapse_epics(epics: list[dict], ideas: list[dict]) -> tuple[list[dict], list[dict]]:
    """Fold each epic's children into one card. Returns (cards, loose ideas).

    An epic replaces its children everywhere on the public page: one card in the
    Roadmap tables, one under By Category, and — once at least one child has
    shipped — one on the Recently Shipped board dated by that child. The card's
    status is derived from the most advanced unfinished child (or `implemented`
    when they are all done) unless the epic sets `status:` explicitly.
    """
    by_id = {e["id"]: e for e in (epics or [])}
    kids: dict[str, list[dict]] = {}
    loose: list[dict] = []
    for idea in ideas:
        eid = idea.get("epic")
        if eid in by_id:
            kids.setdefault(eid, []).append(idea)
        else:
            loose.append(idea)
    cards = []
    for eid, children in kids.items():
        ep = by_id[eid]
        done = [c for c in children if is_shipped(c)]
        todo = [c for c in children if not is_shipped(c)]
        status = ep.get("status")
        if not status:
            status = (min(todo, key=lambda c: STATUS[c["status"]]["rank"])["status"]
                      if todo else "implemented")
        requesters: list[str] = []
        for c in children:
            for p in c.get("_requesters", []):
                if p not in requesters:
                    requesters.append(p)
        cards.append({
            "id": eid,
            "title": ep.get("title", eid),
            "group": ep.get("group"),
            "notes": ep.get("notes"),
            "status": status,
            "children": children,
            "done": len(done),
            "total": len(children),
            "date": max((c.get("date") or "" for c in done), default=""),
            "_requesters": requesters,
            "_epic": True,
        })
    return cards, loose


# ---------------------------------------------------------------------------
# HTML rendering
# ---------------------------------------------------------------------------

def credit_html(idea: dict, shipped: bool) -> str:
    names = [player_name(p) for p in idea.get("_requesters", []) if p]
    if not names:
        return ""
    joined = ", ".join(amp(n) for n in names)
    word = "Credit" if shipped else "Requested by"
    return f'<span class="rm-credit">{word}: {joined}</span>'


def type_badge(idea: dict) -> str:
    """The Defect/Enhancement/Exploit pill, or '' when the idea has no/unknown type."""
    tmeta = TYPES.get(idea.get("type"))
    if not tmeta:
        return ""
    return f'<span class="rm-type rm-type-{tmeta["cls"]}">{tmeta["label"]}</span>'


def idea_row(idea: dict, shipped: bool) -> str:
    meta = STATUS[idea["status"]]
    bits = []
    tbadge = type_badge(idea)
    if tbadge:
        bits.append(tbadge)
    bits.append(f'<span class="rm-badge rm-{meta["cls"]}">{meta["label"]}</span>')
    if shipped and idea.get("date"):
        bits.append(f'<span class="rm-date">{amp(pretty_date(idea["date"]))}</span>')
    credit = credit_html(idea, shipped)
    if credit:
        bits.append(credit)
    # notes is author rich text from the editor; it may contain <ul>/<ol>/<a>.
    # sanitize_notes() reduces it to a safe tag/attr whitelist (and escapes text),
    # so a stray Discord-DOM paste can't break the page layout.
    clean = sanitize_notes(idea.get("notes"))
    notes = f'<div class="rm-notes">{clean}</div>' if clean else ""
    return (
        f'<li class="rm-item" id="idea-{idea["id"]}">'
        f'<div class="rm-title">{amp(idea["title"])}</div>'
        f'<div class="rm-meta">{"".join(bits)}</div>'
        f'{notes}'
        '</li>'
    )


def epic_row(card: dict, shipped: bool) -> str:
    """One epic card: progress, then a checklist of its child ideas.

    Each child keeps its own `id="idea-<id>"` on its bullet, so every existing
    `<a href="#idea-…">` cross-link still resolves after the rollup. A partly
    finished epic renders twice (By Category *and* Recently Shipped); only the
    copy matching its own status board carries the ids, so the anchors stay
    unique and land on the card the Roadmap table links to.
    """
    meta = STATUS[card["status"]]
    anchored = shipped == (meta["board"] == "shipped")
    bits = [f'<span class="rm-badge rm-{meta["cls"]}">{meta["label"]}</span>']
    if shipped and card.get("date"):
        bits.append(f'<span class="rm-date">{amp(pretty_date(card["date"]))}</span>')
    credit = credit_html(card, shipped)
    if credit:
        bits.append(credit)
    clean = sanitize_notes(card.get("notes"))
    notes = f'<div class="rm-notes">{clean}</div>' if clean else ""
    def anchor(prefix: str, oid: str) -> str:
        return f' id="{prefix}-{oid}"' if anchored else ""

    kids = "".join(
        '<li' + anchor("idea", c["id"])
        + f' class="{"done" if is_shipped(c) else "todo"}">{amp(c["title"])}</li>'
        for c in card["children"]
    )
    return (
        '<li class="rm-item rm-epic"' + anchor("epic", card["id"]) + '>'
        f'<div class="rm-title">{amp(card["title"])}'
        f'<span class="rm-epic-prog">{card["done"]} / {card["total"]} complete</span>'
        f'</div>'
        f'<div class="rm-meta">{"".join(bits)}</div>'
        f'{notes}'
        f'<ul class="rm-epic-kids">{kids}</ul>'
        '</li>'
    )


def board_row(item: dict, shipped: bool) -> str:
    """Render either an epic card or a plain idea row."""
    return epic_row(item, shipped) if item.get("_epic") else idea_row(item, shipped)


def group_order(groups: list[dict]) -> list[dict]:
    return sorted(groups, key=lambda g: (g.get("order", 9999), g["title"]))


def render_roadmap_board(groups, ideas) -> str:
    """In progress / up next, grouped by feature theme."""
    by_group: dict[str, list[dict]] = {}
    for idea in ideas:
        if STATUS[idea["status"]]["board"] == "roadmap":
            by_group.setdefault(idea["group"], []).append(idea)
    out = []
    for g in group_order(groups):
        rows = by_group.get(g["id"])
        if not rows:
            continue
        rows.sort(key=lambda i: (STATUS[i["status"]]["rank"], norm_title(i["title"])))
        items = "\n".join(board_row(i, shipped=False) for i in rows)
        out.append(
            f'<h3 id="next-{g["id"]}">{g["title"]}</h3>'
            f'<ul class="rm-list">{items}</ul>'
        )
    return "\n".join(out)


# The "Roadmap" status board: one table per status, in workflow order. Each row
# links into the matching card down in the "By Category" board. `unlikely` ("Not
# likely to implement") is intentionally omitted here — those still show in By Category.
ROADMAP_SUBSECTIONS = [
    ("confirmed", "In Progress"),
    ("manual",    "Needs Manual Finishing"),
    ("design",    "Needs Design Input"),
    ("wip",       "Up Next"),
    ("soon",      "Coming Soon"),
    ("later",     "Coming Later"),
    ("planned",   "Under Consideration"),
]


def roadmap_subsections_present(ideas) -> list[tuple[str, str]]:
    """The (status, heading) pairs that actually have at least one idea."""
    have = {i["status"] for i in ideas}
    return [(s, h) for s, h in ROADMAP_SUBSECTIONS if s in have]


def render_roadmap_tables(groups, ideas) -> str:
    """Roadmap board: in-flight ideas as Name/Type/Category tables, grouped by status."""
    ordered = group_order(groups)
    title_of = {g["id"]: g["title"] for g in ordered}
    order_of = {g["id"]: n for n, g in enumerate(ordered)}
    out = []
    for status, heading in roadmap_subsections_present(ideas):
        rows = [i for i in ideas if i["status"] == status]
        rows.sort(key=lambda i: (order_of.get(i["group"], 9999), norm_title(i["title"])))
        body = []
        for i in rows:
            gid = i["group"]
            cat = (f'<a href="#next-{gid}">{title_of.get(gid, gid)}</a>'
                   if gid in title_of else amp(gid))
            anchor = ("epic-" if i.get("_epic") else "idea-") + i["id"]
            name = (f'{amp(i["title"])} <span class="rm-epic-prog">'
                    f'{i["done"]} / {i["total"]}</span>') if i.get("_epic") \
                else amp(i["title"])
            body.append(
                "<tr>"
                f'<td><a href="#{anchor}">{name}</a></td>'
                f'<td>{type_badge(i)}</td>'
                f'<td>{cat}</td>'
                "</tr>"
            )
        out.append(
            f'<h3 id="roadmap-{status}">{heading}</h3>'
            '<table class="rm-roadmap-table change-table">'
            '<thead><tr><th>Name</th><th>Type</th><th>Category</th></tr></thead>'
            f'<tbody>{"".join(body)}</tbody></table>'
        )
    return "\n".join(out)


def render_summary_pivot(ideas) -> str:
    """At-a-glance counts: idea type (rows) x lifecycle stage (columns), with totals."""
    cols = list(PIVOT_COLUMNS)

    counts: dict[tuple[str, str], int] = {}
    for i in ideas:
        t = i.get("type")
        if t not in TYPES:
            continue
        key = (t, pivot_column(i["status"]))
        counts[key] = counts.get(key, 0) + 1

    head = "".join(f"<th>{c}</th>" for c in cols)
    rows = []
    col_tot = {c: 0 for c in cols}
    for t in TYPES:
        cells, rtot = [], 0
        for c in cols:
            n = counts.get((t, c), 0)
            rtot += n
            col_tot[c] += n
            cells.append(f"<td>{n}</td>")
        rows.append(
            f'<tr><th scope="row">{TYPES[t]["label"]}</th>'
            f'{"".join(cells)}<td class="rm-pivot-tot">{rtot}</td></tr>'
        )
    grand = sum(col_tot.values())
    foot_cells = "".join(f'<td class="rm-pivot-tot">{col_tot[c]}</td>' for c in cols)
    rows.append(
        f'<tr class="rm-pivot-total"><th scope="row">Total</th>'
        f'{foot_cells}<td class="rm-pivot-tot">{grand}</td></tr>'
    )
    return (
        '<table class="rm-pivot">'
        f'<thead><tr><th></th>{head}<th class="rm-pivot-tot">Total</th></tr></thead>'
        f'<tbody>{"".join(rows)}</tbody></table>'
    )


def render_shipped_board(ideas) -> str:
    """Recently shipped, newest first.

    An epic lands here as soon as *any* child has shipped — dated by that child —
    so partly-finished projects still show their progress instead of spraying one
    card per small fix.
    """
    rows = [i for i in ideas
            if STATUS[i["status"]]["board"] == "shipped"
            or (i.get("_epic") and i["done"])]
    rows.sort(key=lambda i: (i.get("date") or "", i["id"]), reverse=True)
    items = "\n".join(board_row(i, shipped=True) for i in rows)
    return f'<ul class="rm-list">{items}</ul>'


STYLE = """  <style>
    .mw-layout { display: flex; gap: 2.5em; align-items: flex-start; }
    .mw-toc-pane { flex: 0 0 220px; position: sticky; top: 1.5em;
      max-height: calc(100vh - 3em); overflow-y: auto; }
    .mw-content { flex: 1; min-width: 0; }
    @media (max-width: 700px) {
      .mw-layout { flex-direction: column; }
      .mw-toc-pane { position: static; max-height: none; flex: none; width: 100%; }
    }
    .toc { background: var(--card); border: 1px solid var(--border);
      border-radius: 4px; padding: 1em 1.2em; }
    .toc h2 { font-size: 1em; margin: 0 0 0.5em; border: none; padding: 0;
      color: var(--muted); letter-spacing: 0.04em; text-transform: uppercase; }
    .toc ol { margin: 0; padding-left: 1.3em; }
    .toc li { margin: 0.2em 0; }
    .toc a { color: var(--link); }

    .section-header { background: rgba(107,58,28,0.08);
      border-left: 4px solid var(--accent); padding: 0.5em 1em;
      margin: 2em 0 0.8em; border-radius: 0 4px 4px 0; }
    .section-header h2 { margin: 0; border: none; padding: 0; }
    .section-header .section-sub { font-size: 0.88em; color: var(--muted);
      margin: 0.2em 0 0; }

    .tip-box { background: rgba(30,30,60,0.07);
      border-left: 4px solid var(--accent-soft); border-radius: 0 4px 4px 0;
      padding: 0.7em 1.1em; margin: 0.8em 0 1em; font-size: 0.93em; }
    .tip-box p { margin: 0.3em 0; }

    /* Prominent "as of" disclaimer banner */
    .asof-banner { background: rgba(107,58,28,0.12);
      border: 1px solid var(--accent); border-left: 6px solid var(--accent);
      border-radius: 4px; padding: 0.9em 1.2em; margin: 0 0 1.2em;
      display: flex; flex-wrap: wrap; align-items: baseline; gap: 0.6em; }
    .asof-banner .asof-tag { font-weight: 700; text-transform: uppercase;
      letter-spacing: 0.05em; color: var(--accent); white-space: nowrap; }
    .asof-banner .asof-note { color: var(--muted); font-size: 0.93em; }

    .rm-list { list-style: none; margin: 0.4em 0 1.4em; padding: 0; }
    .rm-item { border: 1px solid var(--border); border-radius: 4px;
      background: var(--card); padding: 0.6em 0.9em; margin: 0.45em 0; }
    .rm-title { font-weight: 600; }
    .rm-meta { margin-top: 0.35em; display: flex; flex-wrap: wrap;
      align-items: center; gap: 0.5em; font-size: 0.85em; }
    .rm-notes { margin: 0.4em 0 0; font-size: 0.88em; color: var(--muted); }
    .rm-notes ul, .rm-notes ol { margin: 0.3em 0; padding-left: 1.4em; }
    .rm-notes a { color: var(--link); }
    .rm-date { color: var(--muted); }
    .rm-credit { color: var(--muted); font-style: italic; }

    /* Epic card: one umbrella item standing in for its child ideas, with an
       x/y progress count and a ✔/○ checklist of the children. */
    .rm-epic { border-left: 4px solid var(--accent); }
    .rm-epic-prog { margin-left: 0.6em; font-size: 0.82em; font-weight: 600;
      color: var(--muted); border: 1px solid var(--border); border-radius: 999px;
      padding: 0.1em 0.6em; white-space: nowrap; }
    .rm-epic-kids { list-style: none; margin: 0.5em 0 0; padding: 0;
      font-size: 0.9em; }
    .rm-epic-kids li { padding: 0.1em 0 0.1em 1.5em; position: relative; }
    .rm-epic-kids li::before { position: absolute; left: 0.2em; }
    .rm-epic-kids li.done::before { content: "\\2714"; color: #3a7d44; }
    .rm-epic-kids li.todo::before { content: "\\25CB"; color: var(--muted); }
    .rm-epic-kids li.todo { color: var(--muted); }

    .rm-badge { display: inline-block; padding: 0.1em 0.6em; border-radius: 999px;
      font-size: 0.8em; font-weight: 600; white-space: nowrap;
      border: 1px solid var(--border); }
    .rm-shipped { background: rgba(40,90,50,0.16); border-color: #3a7d44; }
    .rm-testing { background: rgba(40,90,50,0.10); border-color: #3a7d44; }
    .rm-active  { background: rgba(30,90,160,0.16); border-color: #2e6fb0; }
    .rm-manual  { background: rgba(70,110,140,0.16); border-color: #4a7a9b; }
    .rm-design  { background: rgba(200,150,30,0.18); border-color: #b8860b; }
    .rm-queued  { background: rgba(107,58,28,0.14); border-color: var(--accent); }
    .rm-soon    { background: rgba(107,58,28,0.09); border-color: var(--accent-soft); }
    .rm-later   { background: rgba(120,120,120,0.18); border-color: var(--accent-soft); }
    .rm-planned { background: rgba(120,120,120,0.14); }
    .rm-unlikely { background: rgba(120,120,120,0.08); color: var(--muted);
      border-style: dashed; }

    /* Idea type (Defect / Enhancement / Exploit) — color-coded so the kind of
       contribution is scannable at a glance. Defect=red, Enhancement=blue,
       Exploit=purple. */
    .rm-type { display: inline-block; padding: 0.1em 0.6em; border-radius: 999px;
      font-size: 0.8em; font-weight: 600; white-space: nowrap; border: 1px solid; }
    .rm-type-defect      { background: rgba(200,50,50,0.16);  border-color: #c0392b; color: #c0392b; }
    .rm-type-enhancement { background: rgba(40,110,200,0.16); border-color: #2e6fb0; color: #2e6fb0; }
    .rm-type-exploit     { background: rgba(140,70,200,0.18); border-color: #7d4fc0; color: #7d4fc0; }

    .rm-cost-table td.rm-cost, .rm-cost-table th:first-child { white-space: nowrap; }
    .rm-cost { font-weight: 600; text-align: center; }
    .change-table td, .change-table th { font-size: 0.92em; vertical-align: top; }

    /* Roadmap status board: compact Name/Type/Category tables that link down
       into the matching cards under "By Category". */
    .rm-roadmap-table { width: 100%; border-collapse: collapse; margin: 0.4em 0 1.4em; }
    .rm-roadmap-table th, .rm-roadmap-table td { text-align: left; padding: 0.4em 0.7em;
      border-bottom: 1px solid var(--border); vertical-align: top; }
    .rm-roadmap-table thead th { color: var(--muted); font-size: 0.82em;
      text-transform: uppercase; letter-spacing: 0.04em; }
    .rm-roadmap-table td:nth-child(2), .rm-roadmap-table td:nth-child(3),
    .rm-roadmap-table th:nth-child(2), .rm-roadmap-table th:nth-child(3) { white-space: nowrap; }
    .rm-roadmap-table a { color: var(--link); }

    /* About-section summary pivot: idea type x lifecycle stage. */
    .rm-pivot-caption { margin: 1em 0 0.3em; font-weight: 600; }
    .rm-pivot { border-collapse: collapse; margin: 0 0 1.2em; }
    .rm-pivot th, .rm-pivot td { border: 1px solid var(--border); padding: 0.35em 0.8em; }
    .rm-pivot thead th { color: var(--muted); font-size: 0.82em; font-weight: 600;
      text-transform: uppercase; letter-spacing: 0.04em; background: var(--card); }
    .rm-pivot td { text-align: right; }
    .rm-pivot tbody th[scope="row"] { text-align: left; font-weight: 600; }
    .rm-pivot .rm-pivot-tot { font-weight: 700; }
    .rm-pivot .rm-pivot-total th, .rm-pivot .rm-pivot-total td { font-weight: 700;
      border-top: 2px solid var(--accent-soft); }
    h2, h3 { scroll-margin-top: 1.5em; }
  </style>"""


def canon_ideas(data: dict) -> list[dict]:
    """The published, dupe-merged idea list.

    Both the page and the credit sidecar are built from this one list, and it is
    computed ONCE per run: merge_dupes() appends to each idea's ``_requesters``
    in place, so calling it twice on the same parsed YAML would credit every
    submitter to their own idea twice over.
    """
    return merge_dupes(publishable(data.get("ideas", [])))


def build_html(data: dict, canon: list[dict] | None = None) -> str:
    meta = data.get("meta", {})
    groups = data.get("groups", [])

    canon = canon_ideas(data) if canon is None else canon
    # Boards render epic cards in place of their children; the pivot keeps
    # counting the underlying ideas.
    cards, loose = collapse_epics(data.get("epics", []) or [], canon)
    items = loose + cards
    asof = pretty_asof(meta.get("as_of", ""))

    # TOC: status subsections of the Roadmap board that have at least one idea
    toc_roadmap = "\n".join(
        f'<li><a href="#roadmap-{s}">{h}</a></li>'
        for s, h in roadmap_subsections_present(items)
    )

    # TOC: By Category groups that actually have queued items
    roadmap_groups = group_order([
        g for g in groups
        if any(i["group"] == g["id"] and STATUS[i["status"]]["board"] == "roadmap"
               for i in items)
    ])
    toc_next = "\n".join(
        f'<li><a href="#next-{g["id"]}">{g["title"]}</a></li>' for g in roadmap_groups
    )

    body = f"""<body>
  <main>
{STYLE}
  <div class="mw-layout">
  <aside class="mw-toc-pane">
    <nav class="toc" aria-label="Page contents">
      <h2>Contents</h2>
      <ol>
        <li><a href="#about">About this page</a></li>
        <li><a href="#roadmap">Roadmap</a>
          <ol style="margin:0.2em 0 0 0;">
{toc_roadmap}
          </ol>
        </li>
        <li><a href="#by-category">By Category</a>
          <ol style="margin:0.2em 0 0 0;">
{toc_next}
          </ol>
        </li>
        <li><a href="#shipped">Recently Shipped</a></li>
      </ol>
    </nav>
  </aside>
  <div class="mw-content">

<h1>Roadmap &amp; Player Ideas &mdash; Homer's LOTR</h1>

<div class="asof-banner">
  <span class="asof-tag">As of {asof}</span>
</div>

<p id="about">{meta.get("intro", "")}</p>

<p class="rm-pivot-caption">Idea counts by type and stage:</p>
{render_summary_pivot(canon)}

<hr>

<div class="section-header" id="roadmap">
  <h2>Roadmap</h2>
  <p class="section-sub">Where the module is heading, by stage &mdash; from "In Progress" through "Up Next", "Coming Soon", "Coming Later" and "Under Consideration". Click any name or category to jump to its full detail under <a href="#by-category">By Category</a> below.</p>
</div>
{render_roadmap_tables(groups, items)}

<hr>

<div class="section-header" id="by-category">
  <h2>By Category</h2>
  <p class="section-sub">The same in-flight ideas, grouped by feature theme with full notes. Each item's badge shows its stage: "In progress" is being actively worked; "Up next" is queued, with "Soon" and "Later" progressively further out; "Under consideration" is captured but not yet committed to; "Not likely to implement" is logged but probably won't happen.</p>
</div>
{render_roadmap_board(groups, items)}

<hr>

<div class="section-header" id="shipped">
  <h2>Recently Shipped</h2>
  <p class="section-sub">Player-suggested fixes and features already live on the server, newest first &mdash; with merit credited to whoever suggested them.</p>
</div>
{render_shipped_board(items)}

  </div>
  </div>
  </main>
</body>"""

    return f"""<!doctype html>
<html lang="en">
<head>
  <meta charset="utf-8">
  <title>Roadmap & Player Ideas</title>
  <!-- Literal '&' is intentional: the wiki build re-extracts this <title> via
       regex and HTML-escapes it; pre-escaping here would double-escape. -->
  <!-- @menu 'Activity' -->
  <!-- @order 0 -->
  <!-- The wiki build regex-scans the raw file text for these directives to
       decide which nav dropdown the page lands in (Activity, not the default
       Documents). They MUST live in this template: this whole file is
       regenerated on every gen-roadmap.py run, so a hand-added directive in
       docs.manual/Roadmap.html is wiped and the page silently falls back to
       the Documents menu. -->
  <link rel="stylesheet" href="../assets/style.css">
</head>
{body}
</html>
"""


def write_credits(data: dict, canon: list[dict]) -> int:
    """Write roadmap-credits.json — who submitted and who tested what.

    The wiki build (nwn_manager) puts idea counts on the players index and a
    per-player idea list on each player page, but the ideas live here, in YAML,
    in a different repo. Rather than teach the wiki engine to parse roadmap.yaml
    — which would fork the status table, the dupe merge and the `hidden` rule
    into a second implementation that could silently drift — this hands it the
    already-resolved answer.

    Written from `canon`, the same list render_summary_pivot() counts, so a
    player page and the roadmap page cannot disagree about a total. `hidden`
    ideas are gone before this point (publishable() runs inside canon_ideas), so
    no unpublished credit can leak onto a player page.

    Returns the number of ideas written.
    """
    group_title = {g["id"]: g["title"] for g in data.get("groups", []) or []}
    out_ideas = []
    for i in canon:
        # An idea with no type is not a player-classifiable submission (epic
        # placeholders, admin chores); it is carried anyway, with type null, so
        # the consumer decides rather than being silently short-changed.
        out_ideas.append({
            "id": i["id"],
            "title": i["title"],
            "type": i.get("type"),
            "status": i["status"],
            "column": pivot_column(i["status"]),
            "date": i.get("date") or "",
            # Every canonical idea carries this id exactly once on the rendered
            # page — on its own <li>, or as an epic child on the epic's board.
            "anchor": f"idea-{i['id']}",
            "group": i.get("group") or "",
            "group_title": group_title.get(i.get("group") or "", ""),
            "requesters": list(i.get("_requesters") or []),
            "uat_credits": [
                {"player": c.get("player") or "",
                 "awarded": bool(c.get("awarded")),
                 "date": c.get("date") or ""}
                for c in (i.get("uat_credits") or [])
                if isinstance(c, dict) and c.get("player")
            ],
        })

    payload = {
        "generated_at": datetime.now().strftime("%Y-%m-%d %H:%M:%S"),
        "page": "manual/Roadmap.html",
        "columns": list(PIVOT_COLUMNS),
        "types": [{"key": t, "label": TYPES[t]["label"],
                   "merit": MERIT_POINTS.get(t)} for t in TYPES],
        "statuses": {k: {"label": v["label"], "rank": v["rank"],
                         "board": v["board"], "column": pivot_column(k)}
                     for k, v in STATUS.items()},
        "ideas": out_ideas,
    }
    CREDITS_PATH.write_text(
        json.dumps(payload, indent=2, ensure_ascii=False) + "\n", encoding="utf-8")
    return len(out_ideas)


def main() -> int:
    ap = argparse.ArgumentParser(description=__doc__)
    ap.add_argument("--check", action="store_true", help="validate only, write nothing")
    ap.add_argument("--force", action="store_true",
                    help="render even on a non-dev realm (see the realm guard below)")
    args = ap.parse_args()

    data = yaml.load(YAML_PATH.read_text(encoding="utf-8"), Loader=_YamlLoader)

    errors = validate(data)
    if errors:
        print("roadmap.yaml has errors:", file=sys.stderr)
        for e in errors:
            print(f"  [error] {e}", file=sys.stderr)
        return 1

    resolve_dates(data.get("ideas", []))

    if args.check:
        print("roadmap.yaml OK")
        return 0

    # ---------------------------------------------------------- realm guard --
    # ONLY THE DEV REALM RENDERS THIS PAGE. The roadmap editor runs in dev, and
    # its "Publish to Wiki & DB" button now copies the page it renders into the
    # LIVE realm's docs/ as well, so a player sees a reported issue tracked on
    # homerslotr.com immediately instead of at the next promotion.
    #
    # A season repo must therefore not re-render it: its roadmap.yaml is only as
    # new as the last bin/season-promote.sh, and resolve_dates() reads shipped
    # dates out of LOCAL git — promotion copies the tree, not the history, so
    # dev's commit hashes do not exist there and the dates would degrade. Left
    # unguarded, that realm's nightly bin/refresh-homers-lotr-wiki would quietly
    # overwrite every publish with an older, worse page.
    #
    # Exit 0, not an error: refresh-homers-lotr-wiki and season-promote.sh both
    # print a WARN on a non-zero exit, and skipping here is normal, not a fault.
    role = season_role()
    if role and role != "dev" and not args.force:
        print(f"skipped: this realm is SEASON_ROLE={role}; {OUT_PATH.name} is "
              "published from the dev realm (use --force to override)")
        return 0

    canon = canon_ideas(data)
    html = build_html(data, canon)
    OUT_PATH.parent.mkdir(parents=True, exist_ok=True)
    OUT_PATH.write_text(html, encoding="utf-8")
    n = len(data.get("ideas", []))
    print(f"wrote {OUT_PATH.relative_to(REPO)} ({n} ideas)")

    # Same realm guard, same run: the sidecar is the credit half of this page,
    # and a build that publishes one while leaving the other stale would put
    # counts on the players index that the roadmap page contradicts.
    n_credits = write_credits(data, canon)
    print(f"wrote {CREDITS_PATH.relative_to(REPO)} ({n_credits} published ideas)")
    return 0


if __name__ == "__main__":
    sys.exit(main())
