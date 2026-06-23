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
import re
import subprocess
import sys
from pathlib import Path

import yaml

REPO = Path(__file__).resolve().parent.parent
YAML_PATH = REPO / "roadmap.yaml"
OUT_PATH = REPO / "docs.manual" / "Roadmap.html"

# Status -> (badge label, css modifier, which board it belongs to).
# board "shipped" = Recently Shipped timeline; "roadmap" = In Progress / Up Next.
STATUS = {
    "awarded":     {"label": "Shipped · Merit awarded", "cls": "shipped",  "board": "shipped", "rank": 0},
    "implemented": {"label": "Shipped · in testing",     "cls": "testing",  "board": "shipped", "rank": 1},
    "confirmed":   {"label": "In progress",                  "cls": "active",   "board": "roadmap", "rank": 0},
    "wip":         {"label": "Up next",                      "cls": "queued",   "board": "roadmap", "rank": 1},
    "soon":        {"label": "Soon",                         "cls": "soon",     "board": "roadmap", "rank": 2},
    "later":       {"label": "Later",                        "cls": "later",    "board": "roadmap", "rank": 3},
    "planned":     {"label": "Under consideration",          "cls": "planned",  "board": "roadmap", "rank": 4},
    "unlikely":    {"label": "Not likely to implement",      "cls": "unlikely", "board": "roadmap", "rank": 5},
}

# Idea kind -> (badge label, css modifier). The merit value of a *shipped*
# (awarded) idea depends on its type: Defect=1, Enhancement=2, Exploit=3.
TYPES = {
    "Defect":      {"label": "Defect",      "cls": "defect"},
    "Enhancement": {"label": "Enhancement", "cls": "enhancement"},
    "Exploit":     {"label": "Exploit",     "cls": "exploit"},
}
MERIT_POINTS = {"Defect": 1, "Enhancement": 2, "Exploit": 3}

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

    seen: dict[str, int] = {}
    for i, idea in enumerate(ideas):
        iid = idea.get("id")
        if not iid:
            errors.append(f"idea #{i} is missing an id")
            continue
        if iid in seen:
            errors.append(f"duplicate id '{iid}' (also at index {seen[iid]})")
        seen[iid] = i
        if idea.get("status") not in STATUS:
            errors.append(f"'{iid}': unknown status {idea.get('status')!r}")
        if idea.get("group") not in group_ids:
            errors.append(f"'{iid}': unknown group {idea.get('group')!r}")
        if idea.get("type") is not None and idea.get("type") not in TYPES:
            errors.append(f"'{iid}': unknown type {idea.get('type')!r}")

    # dupe_of must point at a real id, and the target must not itself be a dupe.
    for idea in ideas:
        dof = idea.get("dupe_of")
        if dof and dof not in seen:
            errors.append(f"'{idea.get('id')}': dupe_of points to unknown id '{dof}'")

    # Similar-title warning among non-merged ideas (duplicate-idea guard).
    canon = [i for i in ideas if not i.get("dupe_of")]
    for a in range(len(canon)):
        for b in range(a + 1, len(canon)):
            na, nb = norm_title(canon[a]["title"]), norm_title(canon[b]["title"])
            if not na or not nb:
                continue
            wa, wb = set(na.split()), set(nb.split())
            overlap = len(wa & wb) / max(1, min(len(wa), len(wb)))
            if overlap >= 0.7 and canon[a]["group"] == canon[b]["group"]:
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


def idea_row(idea: dict, shipped: bool) -> str:
    meta = STATUS[idea["status"]]
    bits = []
    if idea.get("type") in TYPES:
        tmeta = TYPES[idea["type"]]
        bits.append(f'<span class="rm-type rm-type-{tmeta["cls"]}">{tmeta["label"]}</span>')
    bits.append(f'<span class="rm-badge rm-{meta["cls"]}">{meta["label"]}</span>')
    if shipped and idea.get("date"):
        bits.append(f'<span class="rm-date">{amp(pretty_date(idea["date"]))}</span>')
    credit = credit_html(idea, shipped)
    if credit:
        bits.append(credit)
    # notes is trusted author HTML (rich text from the editor); render as a block
    # so it may contain <ul>/<ol>. amp() escapes lone & without touching tags.
    notes = (f'<div class="rm-notes">{amp(idea["notes"])}</div>'
             if idea.get("notes") else "")
    return (
        f'<li class="rm-item" id="idea-{idea["id"]}">'
        f'<div class="rm-title">{amp(idea["title"])}</div>'
        f'<div class="rm-meta">{"".join(bits)}</div>'
        f'{notes}'
        '</li>'
    )


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
        items = "\n".join(idea_row(i, shipped=False) for i in rows)
        out.append(
            f'<h3 id="next-{g["id"]}">{g["title"]}</h3>'
            f'<ul class="rm-list">{items}</ul>'
        )
    return "\n".join(out)


def render_shipped_board(ideas) -> str:
    """Recently shipped, newest first."""
    rows = [i for i in ideas if STATUS[i["status"]]["board"] == "shipped"]
    rows.sort(key=lambda i: (i.get("date") or "", i["id"]), reverse=True)
    items = "\n".join(idea_row(i, shipped=True) for i in rows)
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

    .rm-badge { display: inline-block; padding: 0.1em 0.6em; border-radius: 999px;
      font-size: 0.8em; font-weight: 600; white-space: nowrap;
      border: 1px solid var(--border); }
    .rm-shipped { background: rgba(40,90,50,0.16); border-color: #3a7d44; }
    .rm-testing { background: rgba(40,90,50,0.10); border-color: #3a7d44; }
    .rm-active  { background: rgba(30,90,160,0.16); border-color: #2e6fb0; }
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
    h2, h3 { scroll-margin-top: 1.5em; }
  </style>"""


def build_html(data: dict) -> str:
    meta = data.get("meta", {})
    groups = data.get("groups", [])
    ideas = data.get("ideas", [])

    canon = merge_dupes(ideas)
    asof = pretty_asof(meta.get("as_of", ""))

    # TOC: roadmap groups that actually have queued items
    roadmap_groups = group_order([
        g for g in groups
        if any(i["group"] == g["id"] and STATUS[i["status"]]["board"] == "roadmap"
               for i in canon)
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
        <li><a href="#next">Roadmap &mdash; In Progress &amp; Up Next</a>
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

<hr>

<div class="section-header" id="next">
  <h2>Roadmap &mdash; In Progress &amp; Up Next</h2>
  <p class="section-sub">Where the module is heading, grouped by feature. "In progress" is being actively worked; "Up next" is queued, with "Soon" and "Later" progressively further out; "Under consideration" is captured but not yet committed to; "Not likely to implement" is logged but probably won't happen.</p>
</div>
{render_roadmap_board(groups, canon)}

<hr>

<div class="section-header" id="shipped">
  <h2>Recently Shipped</h2>
  <p class="section-sub">Player-suggested fixes and features already live on the server, newest first &mdash; with merit credited to whoever suggested them.</p>
</div>
{render_shipped_board(canon)}

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
  <link rel="stylesheet" href="../assets/style.css">
</head>
{body}
</html>
"""


def main() -> int:
    ap = argparse.ArgumentParser(description=__doc__)
    ap.add_argument("--check", action="store_true", help="validate only, write nothing")
    args = ap.parse_args()

    data = yaml.safe_load(YAML_PATH.read_text(encoding="utf-8"))

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

    html = build_html(data)
    OUT_PATH.parent.mkdir(parents=True, exist_ok=True)
    OUT_PATH.write_text(html, encoding="utf-8")
    n = len(data.get("ideas", []))
    print(f"wrote {OUT_PATH.relative_to(REPO)} ({n} ideas)")
    return 0


if __name__ == "__main__":
    sys.exit(main())
