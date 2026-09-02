#!/usr/bin/env python3
"""Release notes for the commits that are in the dev realm but not yet in a season.

Two audiences, one dataset:

    --audience testers   what just landed on the test realm and what still needs
                         checking — published while the diff is open
    --audience players   what this update contains — published when
                         bin/season-promote.sh closes the diff
    --audience admin     both, plus hidden items, plus the commits no roadmap
                         item claimed (the "nothing silently vanished" check)

## Why this is deterministic

It is not a git-log summariser. roadmap.yaml already carries the player-facing
release note for every shipped item, in `commit:` + `notes:`, so the join is
exact:

    base = last promoted dev sha  ->  git log base..HEAD  ->  set of shas
                                  ->  ideas whose commit: is in that set
                                  ->  their notes / type / group / manual_steps

Run it twice on the same range and you get byte-identical output. `--flavor`
(below) keeps that property by caching its result to a sidecar.

## The baseline

The dev repo and a season repo have DISJOINT histories (the season was cut as an
orphan at cutover), so `git log s2/main..main` is impossible. The link is
recorded twice, and both are consulted in this order:

  1. --since REF                          (explicit, always wins)
  2. the target repo's newest commit subject, "Promote from dev @<sha>"
  3. the newest promote/s<N>/* tag in this repo

bin/season-promote.sh writes both on every promotion. The commit subject is
preferred because the tag is force-moved and can be lost; the commit cannot.

## The operational trap

`season-promote.sh --apply` moves the tag AND writes the target's new
"Promote from dev @<sha>". So generate the notes BEFORE promoting — afterwards
the range is empty and you must pass `--since <the previous base>` by hand.

    python3 bin/gen-release-notes.py --audience testers
    python3 bin/gen-release-notes.py --audience players --out notes.md
    python3 bin/gen-release-notes.py --audience admin --since 9103a153141
"""
from __future__ import annotations

import argparse
import datetime as _dt
import hashlib
import html as _html
import importlib.util
import json
import re
import subprocess
import sys
from pathlib import Path

REPO = Path(__file__).resolve().parent.parent
sys.path.insert(0, str(REPO / "bin"))

import roadmap_publish as PUB  # noqa: E402  (also gives us PUB.GEN = gen-roadmap.py)

import yaml  # noqa: E402

try:
    from yaml import CSafeLoader as _YamlLoader
except ImportError:                                  # pragma: no cover
    from yaml import SafeLoader as _YamlLoader

GEN = PUB.GEN
SERVER_ENV = REPO / "server.env"
FLAVOR_DIR = REPO / "release-notes"
DEFAULT_TARGET = REPO.parent / "nwn_homers_lotr_s2"
# Some roadmap items are wiki/tooling work, so their `commit:` names a commit in
# the generator repo rather than this one. Without checking here they would look
# like typos. See ENV_EXTERNAL below.
MANAGER_REPO = REPO.parent / "nwn_manager"

# Commits that are bookkeeping, not content. Anything matching these is expected
# to have no roadmap item and is not reported as unattributed.
NOISE_RE = re.compile(
    r"^(Auto Wiki Activity Refresh"
    r"|Full wiki republish"
    r"|[Rr]oadmap[:\s]"
    r"|Promote from dev"
    r"|Merge (branch|pull request)"
    r")"
)

PROMOTE_SUBJECT_RE = re.compile(r"Promote from dev @([0-9a-f]{7,40})")
SHA_SPLIT_RE = re.compile(r"[\s,;]+")


# --------------------------------------------------------------------- git --

def git(*args: str, cwd: Path = REPO) -> str:
    out = subprocess.run(["git", *args], cwd=str(cwd),
                         capture_output=True, text=True)
    if out.returncode != 0:
        raise RuntimeError(f"git {' '.join(args)} failed: {out.stderr.strip()}")
    return out.stdout


def git_ok(*args: str, cwd: Path = REPO) -> bool:
    return subprocess.run(["git", *args], cwd=str(cwd),
                          capture_output=True, text=True).returncode == 0


def season_env(key: str) -> str:
    """One value out of server.env's SEASON_ block. Last assignment wins.

    Same one-line parse as gen-roadmap.py's season_role(); kept to the SEASON_*
    keys deliberately, so nothing else in server.env can reach the output.
    """
    if not key.startswith("SEASON_"):
        raise ValueError(f"refusing to read non-season key {key!r}")
    try:
        text = SERVER_ENV.read_text(encoding="utf-8")
    except OSError:
        return ""
    val = ""
    for ln in text.splitlines():
        m = re.match(rf"\s*(?:export\s+)?{re.escape(key)}\s*=\s*(.+?)\s*$", ln)
        if m:
            val = m.group(1).strip()
    if val[:1] in ('"', "'"):
        end = val.find(val[0], 1)
        return val[1:end] if end != -1 else val[1:]
    return val.split("#", 1)[0].strip()


def resolve_base(target: Path, since: str | None) -> tuple[str, str]:
    """(full sha, provenance) of the last promoted dev commit."""
    if since:
        if not git_ok("rev-parse", "--verify", f"{since}^{{commit}}"):
            raise SystemExit(f"error: --since {since!r} does not resolve in this repo")
        return git("rev-parse", since).strip(), f"--since {since}"

    if target.is_dir() and (target / ".git").exists():
        # NOT the target's HEAD: a season repo commits its own unpromoted files
        # (docs/, index.html, the wiki refresh) on top of every promotion, so
        # the newest promote commit is usually several commits back.
        try:
            subj = git("log", "-1", "--format=%s", "--grep=Promote from dev",
                       "main", cwd=target).strip()
        except RuntimeError:
            subj = ""
        m = PROMOTE_SUBJECT_RE.search(subj)
        if m and git_ok("cat-file", "-e", f"{m.group(1)}^{{commit}}"):
            return (git("rev-parse", m.group(1)).strip(),
                    f"{target.name}'s newest 'Promote from dev @{m.group(1)}'")

    # promote/s<N>/<date> is two path components deep, so a single * misses it.
    tags = git("for-each-ref", "--sort=-creatordate", "--format=%(refname:short)",
               "refs/tags/promote/**").split()
    for t in tags:
        if git_ok("rev-parse", "--verify", f"{t}^{{commit}}"):
            return git("rev-parse", f"{t}^{{commit}}").strip(), f"tag {t}"

    raise SystemExit("error: could not resolve a baseline — no target repo promote "
                     "commit and no promote/* tag. Pass --since <ref>.")


def commits_in_range(base: str, head: str = "HEAD") -> list[dict]:
    fmt = "%H%x1f%h%x1f%ad%x1f%s"
    out = git("log", f"{base}..{head}", f"--format={fmt}", "--date=short")
    rows = []
    for ln in out.splitlines():
        if not ln.strip():
            continue
        full, short, date, subj = ln.split("\x1f", 3)
        rows.append({"sha": full, "short": short, "date": date, "subject": subj})
    return rows


# ------------------------------------------------------------- the join --

def idea_shas(idea: dict) -> list[str]:
    raw = idea.get("commit")
    if not raw:
        return []
    return [t.strip("()[[]<>") for t in SHA_SPLIT_RE.split(str(raw)) if t.strip()]


def match_ideas(ideas: list[dict], commits: list[dict]) -> tuple[list[dict], set[str]]:
    """(ideas whose commit: lands in the range, the shas they claimed).

    `commit:` holds abbreviated hashes, sometimes more than one, so match by
    prefix against the full shas of the range.
    """
    full = [c["sha"] for c in commits]
    hit_ideas, claimed = [], set()
    for idea in ideas:
        mine = set()
        for tok in idea_shas(idea):
            if len(tok) < 7:
                continue
            for sha in full:
                if sha.startswith(tok):
                    mine.add(sha)
        if mine:
            hit_ideas.append(idea)
            claimed |= mine
    return hit_ideas, claimed


def plain(s) -> str:
    """roadmap HTML (or an HTML-escaped group title) as plain text."""
    return PUB.html_to_plain(str(s or ""))


def one_line(s) -> str:
    return " ".join(plain(s).split())


def type_prefix(idea: dict) -> str:
    return PUB.TYPE_PREFIX.get(idea.get("type"), PUB.DEFAULT_PREFIX)


def visible(ideas: list[dict]) -> list[dict]:
    """What a player may see: never a hidden item, never a merged duplicate."""
    return [i for i in ideas if not i.get("hidden") and not i.get("dupe_of")]


def sort_key(idea: dict) -> tuple:
    return (idea.get("date") or "", idea.get("id") or "")


# --------------------------------------------------- environment (per idea) --
#
# Which realm an idea's code is actually in. DERIVED, never stored: it changes
# at every promotion with nobody editing anything, so a field in roadmap.yaml
# would be stale within a day. Consumers get it as a side map, never as a key
# on the idea dict -- the roadmap editor posts the whole ideas array back on
# save, so anything hung on an idea would be written into the YAML.

ENV_LIVE = "live"            # every commit is promoted
ENV_DEV = "dev"              # every commit is still only on the dev realm
ENV_REWORK = "rework"        # promoted AND unpromoted commits: shipped, then a follow-up
ENV_REOPENED = "reopened"    # promoted, but the status went back to unshipped
ENV_UNTRACKED = "untracked"  # a shipped status with no commit: at all
ENV_EXTERNAL = "external"    # the commit lives in nwn_manager (wiki/tooling work)
ENV_MISSING = "missing"      # resolves in neither repo -- a typo
ENV_NONE = ""                # ordinary backlog: not built yet, nothing to say

ENV_LABELS = {
    ENV_LIVE:      "Live",
    ENV_DEV:       "Test realm",
    ENV_REWORK:    "Live · rework on test",
    ENV_REOPENED:  "Reopened after release",
    ENV_UNTRACKED: "Shipped · no commit",
    ENV_EXTERNAL:  "Tooling (nwn_manager)",
    ENV_MISSING:   "Commit not found",
}
ENV_ORDER = (ENV_MISSING, ENV_REOPENED, ENV_REWORK, ENV_DEV, ENV_LIVE,
             ENV_EXTERNAL, ENV_UNTRACKED)


def _rev_list(*args: str, cwd: Path = REPO) -> set[str]:
    try:
        return set(git("rev-list", *args, cwd=cwd).split())
    except RuntimeError:
        return set()


def promotion_index(target: Path | None = None, since: str | None = None) -> dict:
    """Everything needed to say which realm a commit is in.

    Two `git rev-list` calls here plus one in nwn_manager (~10ms all told), and
    a prefix map so the 7-, 11- and 40-char abbreviations that `commit:` mixes
    can all be looked up without a `git rev-parse` per item.
    """
    target = DEFAULT_TARGET if target is None else target
    base, prov = resolve_base(target, since)
    head = git("rev-parse", "HEAD").strip()
    promoted = _rev_list(base)
    unpromoted = _rev_list(f"{base}..{head}")
    # Commits that exist here but are on no branch: amended or rebased away, so
    # a `commit:` pointing at one is stale rather than wrong. Worth telling
    # apart from a genuine typo, because the fix is different.
    orphan = _rev_list("--all", "--reflog") - promoted - unpromoted
    external = (_rev_list("--all", cwd=MANAGER_REPO)
                if (MANAGER_REPO / ".git").exists() else set())

    prefix: dict[str, str] = {}
    for full in promoted | unpromoted | orphan | external:
        for n in range(7, 13):
            prefix.setdefault(full[:n], full)
        prefix[full] = full

    return {"base": base, "head": head, "provenance": prov,
            "promoted": promoted, "unpromoted": unpromoted,
            "orphan": orphan, "external": external, "prefix": prefix,
            "season": season_env("SEASON_NUM")}


_ORPHAN = "_orphan"      # internal: exists here, but on no branch


def _subject(sha: str) -> str:
    try:
        return git("log", "-1", "--format=%s", sha).strip()
    except RuntimeError:
        return ""


def _where(sha: str, index: dict) -> str:
    """Which set a single (possibly abbreviated) sha belongs to."""
    full = index["prefix"].get(sha) or index["prefix"].get(sha[:11]) \
        or index["prefix"].get(sha[:7])
    if not full:
        return ENV_MISSING
    if full in index["promoted"]:
        return ENV_LIVE
    if full in index["unpromoted"]:
        return ENV_DEV
    if full in index.get("orphan", ()):
        return _ORPHAN
    return ENV_EXTERNAL


def classify_idea(idea: dict, index: dict) -> tuple[str, str]:
    """(state, a sentence saying why) for one idea. See the ENV_* table above."""
    shas = [t for t in idea_shas(idea) if len(t) >= 7]
    shipped = PUB.is_shipped(idea)

    if not shas:
        if shipped:
            return ENV_UNTRACKED, ("Shipped, but no commit: is recorded — so it "
                                   "cannot appear in the release notes.")
        return ENV_NONE, ""

    where = {sha: _where(sha, index) for sha in shas}
    kinds = set(where.values())

    stale = sorted(s for s, k in where.items() if k == _ORPHAN)
    if stale:
        # Almost always an amend or a rebase, and the replacement kept the same
        # subject -- so quote it, which is what makes this fixable at a glance.
        subj = _subject(stale[0])
        return ENV_MISSING, (
            f"Commit {', '.join(stale)} exists but is on no branch — amended or "
            f"rebased away. Point commit: at its replacement"
            + (f' (same subject: "{subj}").' if subj else "."))

    bad = sorted(s for s, k in where.items() if k == ENV_MISSING)
    if bad:
        return ENV_MISSING, ("No such commit in this repo or in nwn_manager: "
                             + ", ".join(bad) + ". Likely a typo in commit:.")

    # Tooling work has no realm of its own; say so rather than guess.
    kinds.discard(_ORPHAN)
    if kinds == {ENV_EXTERNAL}:
        return ENV_EXTERNAL, ("Built in the nwn_manager repo (wiki or tooling), "
                              "not in the module — it ships with the wiki, not a "
                              "promotion.")
    kinds.discard(ENV_EXTERNAL)

    season = index.get("season") or "?"
    if kinds == {ENV_DEV}:
        return ENV_DEV, (f"On the dev/test realm only — not yet promoted to "
                         f"season {season}.")
    if kinds == {ENV_LIVE}:
        if not shipped:
            return ENV_REOPENED, (f"Was promoted to season {season}, but its "
                                  f"status is back to '{idea.get('status')}' — "
                                  f"reopened for more work.")
        return ENV_LIVE, f"Live on season {season}."
    if kinds == {ENV_LIVE, ENV_DEV}:
        return ENV_REWORK, (f"Shipped to season {season}, and a follow-up commit "
                            f"is still on the dev/test realm.")
    return ENV_NONE, ""


def classify_all(ideas: list[dict], index: dict) -> dict[str, dict]:
    """{idea id: {state, label, why}} — the side map handed to the editor."""
    out = {}
    for idea in ideas:
        state, why = classify_idea(idea, index)
        if not state:
            continue
        out[idea["id"]] = {"state": state, "label": ENV_LABELS[state], "why": why}
    return out


# ------------------------------------------------------------- flavor --

FLAVOR_SYSTEM = (
    "You write short release notes for a Lord of the Rings themed Neverwinter "
    "Nights persistent world. You are given a list of changes that shipped in "
    "one update, each with an id, a title, a type and a plain-text note.\n\n"
    "Do two things:\n"
    "1. MERGE. Where two or more changes are duplicates of each other, or are "
    "different parts of one visible change, combine them into a single bullet "
    "and list every id you merged.\n"
    "2. REWRITE. Give each bullet one or two sentences of plain, concrete, "
    "player-facing prose. Say what a player will notice. No headings, no "
    "markdown, no bullet characters, no developer detail (no script names, no "
    "file names, no resrefs), no marketing language.\n\n"
    "Every id you were given must appear in exactly one bullet. Never invent a "
    "change that is not in the input."
)

FLAVOR_SCHEMA = {
    "type": "object",
    "properties": {
        "bullets": {
            "type": "array",
            "items": {
                "type": "object",
                "properties": {
                    "ids": {"type": "array", "items": {"type": "string"}},
                    "text": {"type": "string"},
                },
                "required": ["ids", "text"],
            },
        }
    },
    "required": ["bullets"],
}
FLAVOR_PROMPT_VERSION = 2
# A roadmap note runs to several paragraphs; the model only needs enough to
# judge relatedness and write a sentence, and the deterministic fallback still
# renders the note in full. Keeping the payload small is what keeps a wide
# range (a whole season's worth of items) inside one context window.
FLAVOR_NOTE_CHARS = 900
FLAVOR_CTX_MIN, FLAVOR_CTX_MAX = 8192, 32768


def _clip(text: str, limit: int) -> str:
    if len(text) <= limit:
        return text
    cut = text[:limit]
    space = cut.rfind(" ")
    return (cut[:space] if space > limit // 2 else cut).rstrip() + " …"


def flavor_input(ideas: list[dict]) -> list[dict]:
    """Exactly what is sent to the LAN model — nothing from server.env, ever."""
    return [{
        "id": i["id"],
        "title": one_line(i.get("title")),
        "type": i.get("type") or "",
        "group": i.get("group") or "",
        "note": _clip(plain(i.get("notes")), FLAVOR_NOTE_CHARS),
    } for i in sorted(ideas, key=lambda i: i["id"])]


def available_models() -> list[tuple[str, str]]:
    """[(name, source)] for the model picker. Never raises.

    The aliases always come back, so a caller (the roadmap editor's dropdown)
    still has something to offer when the box is asleep -- which it often is.
    """
    out = [(alias, "alias") for alias in _llm_config_models()]
    try:
        from llm.client import Client
        for tag in Client().available_models():
            out.append((tag, "installed"))
    except Exception as exc:
        out.append((f"(the LLM box did not answer: {exc})", "error"))
    return out


def _llm_config_models() -> list[str]:
    try:
        from llm import config
        return list(config.MODELS)
    except Exception:
        return ["default"]


def flavor_ctx(user: str) -> int:
    """A context window big enough for this prompt.

    Ollama defaults to 4096, which a range of any size overflows with a bare
    HTTP 400 — sized here rather than fixed so a wide --since still works.
    """
    approx = (len(user) + len(FLAVOR_SYSTEM)) // 3 + 1500
    return max(FLAVOR_CTX_MIN, min(FLAVOR_CTX_MAX, 1 << (approx - 1).bit_length()))


def flavor_fingerprint(payload: list[dict], model: str) -> str:
    """Identity of a flavor pass: these items, rewritten by this model.

    The model is in here because switching models must not silently return the
    previous model's cached text -- the whole point of being able to try a new
    one is seeing what it writes.
    """
    blob = json.dumps([model, payload], sort_keys=True, ensure_ascii=False)
    return hashlib.sha256(blob.encode("utf-8")).hexdigest()[:16]


def flavor_path(base: str, head: str, fingerprint: str) -> Path:
    """One sidecar per (range, item set).

    The fingerprint is in the NAME, not just the body, because --audience
    testers flavors a smaller pool than --audience players over the same range.
    Keyed on the range alone they would evict each other on every switch.
    """
    return FLAVOR_DIR / f"{base[:11]}-{head[:11]}.{fingerprint}.flavor.json"


def load_flavor(path: Path) -> list[dict] | None:
    """A cached flavor pass for this exact item set, if one was written."""
    try:
        doc = json.loads(path.read_text(encoding="utf-8"))
    except (OSError, ValueError):
        return None
    return doc.get("bullets")


def repair_bullets(bullets, ideas: list[dict]) -> tuple[list[dict] | None, list[str]]:
    """Make the model's answer safe to render, or None if nothing survives.

    A 12B model will occasionally drop, duplicate or invent an id, and throwing
    the whole pass away for one bad id means --flavor usually does nothing. So
    repair instead of reject, under one invariant: **every item ends up in
    exactly one bullet**. An item the model forgot gets its own bullet with
    `text: null`, which renders its original roadmap note verbatim — the same
    thing it would have got without --flavor. Nothing can silently vanish.
    """
    valid = {i["id"] for i in ideas}
    warnings: list[str] = []
    if not isinstance(bullets, list) or not bullets:
        return None, ["no bullets returned"]

    out, seen = [], set()
    for b in bullets:
        if not isinstance(b, dict) or not isinstance(b.get("ids"), list):
            warnings.append("dropped a malformed bullet")
            continue
        text = " ".join(str(b.get("text") or "").split())
        if not text:
            warnings.append("dropped a bullet with empty text")
            continue
        ids = []
        for x in b["ids"]:
            x = str(x)
            if x not in valid:
                warnings.append(f"dropped invented id {x!r}")
            elif x in seen:
                warnings.append(f"dropped repeated id {x!r}")
            else:
                ids.append(x)
                seen.add(x)
        if ids:
            out.append({"ids": ids, "text": text})

    for missing in sorted(valid - seen):
        # Its own bullet, un-flavored: the model forgot it, the reader must not.
        warnings.append(f"id {missing!r} was dropped by the model — "
                        f"kept with its original note")
        out.append({"ids": [missing], "text": None})

    if not any(b["text"] for b in out):
        return None, warnings + ["nothing usable came back"]
    out.sort(key=lambda b: sorted(b["ids"]))
    return out, warnings


def run_flavor(ideas: list[dict], base: str, head: str, regen: bool,
               model: str = "default") -> list[dict] | None:
    """Merged, rewritten bullets — or None to fall back to 1:1 rendering.

    Cached to a sidecar so the same range always renders identically and any
    bullet can be hand-edited afterwards.
    """
    if not ideas:
        return None
    payload = flavor_input(ideas)
    fp = flavor_fingerprint(payload, model)
    path = flavor_path(base, head, fp)

    if not regen:
        cached = load_flavor(path)
        if cached is not None:
            return cached

    try:
        from llm.client import Client, LLMError, LLMUnavailable
    except ImportError as exc:                        # pragma: no cover
        print(f"[warn] --flavor: cannot import the LLM client ({exc}); "
              f"writing the deterministic notes instead", file=sys.stderr)
        return None

    client = Client(model)
    ok, msg = client.health()
    if not ok:
        print(f"[warn] --flavor: the LLM box is unreachable ({msg}); "
              f"writing the deterministic notes instead", file=sys.stderr)
        return None

    user = ("Changes in this update:\n\n"
            + json.dumps(payload, indent=2, ensure_ascii=False))
    try:
        raw = client.chat(FLAVOR_SYSTEM, user, FLAVOR_SCHEMA,
                          prompt_version=FLAVOR_PROMPT_VERSION,
                          temperature=0.2, num_ctx=flavor_ctx(user),
                          nonce=None if not regen else int(_dt.datetime.now().timestamp()))
    except (LLMError, LLMUnavailable) as exc:
        print(f"[warn] --flavor: {exc}; writing the deterministic notes instead",
              file=sys.stderr)
        return None

    bullets = (raw or {}).get("bullets") if isinstance(raw, dict) else None
    bullets, warnings = repair_bullets(bullets, ideas)
    for w in warnings:
        print(f"[warn] --flavor: {w}", file=sys.stderr)
    if bullets is None:
        print("[warn] --flavor: writing the deterministic notes instead",
              file=sys.stderr)
        return None

    FLAVOR_DIR.mkdir(parents=True, exist_ok=True)
    path.write_text(json.dumps(
        {"base": base, "head": head, "fingerprint": fp,
         "prompt_version": FLAVOR_PROMPT_VERSION,
         "model": client.short_name, "model_arg": model,
         "generated": _dt.date.today().isoformat(),
         "warnings": warnings,
         "_comment": ("Hand-edit `bullets` freely: `text` is what renders, "
                      "`ids` says which roadmap items it covers, and a null "
                      "`text` falls back to that item's roadmap note. Rerun "
                      "with --regen-flavor to throw this away and re-roll."),
         "bullets": bullets}, indent=2, ensure_ascii=False) + "\n",
        encoding="utf-8")
    merged = sum(1 for b in bullets if len(b["ids"]) > 1)
    print(f"[info] --flavor: {len(ideas)} item(s) -> {len(bullets)} bullet(s)"
          f"{f' ({merged} merged)' if merged else ''}, "
          f"cached in {path.relative_to(REPO)}", file=sys.stderr)
    return bullets


# ------------------------------------------------------------- render --

def md_escape_heading(s: str) -> str:
    return s.replace("\n", " ").strip()


def render_item_body(idea: dict, note_override: str | None) -> list[str]:
    lines = []
    body = note_override if note_override is not None else plain(idea.get("notes"))
    for ln in (body or "").split("\n"):
        lines.append(f"  {ln}".rstrip())
    return lines


def group_titles(doc: dict) -> dict:
    return {g["id"]: plain(g.get("title") or g["id"]) for g in (doc.get("groups") or [])}


def epic_progress(doc: dict) -> dict:
    """epic id -> (title, shipped children, total children) over the WHOLE backlog.

    Computed from every idea, not just the ones in this range — an "x/y" that
    counted only this update's children would be a lie.
    """
    out = {}
    for ep in (doc.get("epics") or []):
        kids = [i for i in (doc.get("ideas") or [])
                if i.get("epic") == ep["id"] and not i.get("hidden")]
        done = [i for i in kids if PUB.is_shipped(i)]
        out[ep["id"]] = (plain(ep.get("title") or ep["id"]), len(done), len(kids))
    return out


def bullets_for(ideas: list[dict], flavored: list[dict] | None) -> list[tuple[list[dict], str | None]]:
    """[(ideas merged into this bullet, flavored text or None)] in stable order."""
    by_id = {i["id"]: i for i in ideas}
    if not flavored:
        return [([i], None) for i in sorted(ideas, key=sort_key, reverse=True)]
    out = []
    for b in flavored:
        members = [by_id[x] for x in b["ids"] if x in by_id]
        if members:
            out.append((members, b["text"]))
    out.sort(key=lambda pair: max(sort_key(i) for i in pair[0]), reverse=True)
    return out


def render_players(ideas: list[dict], doc: dict, flavored) -> list[str]:
    """What's new, grouped by roadmap group; epic children nested under the epic."""
    titles = group_titles(doc)
    epics = epic_progress(doc)
    vis = visible(ideas)
    if not vis:
        return ["_Nothing player-facing in this range._", ""]

    groups: dict[str, list] = {}
    for members, text in bullets_for(vis, flavored):
        gid = members[0].get("group") or "other"
        groups.setdefault(gid, []).append((members, text))

    order = {g["id"]: g.get("order", 999) for g in (doc.get("groups") or [])}
    lines = []
    for gid in sorted(groups, key=lambda g: (order.get(g, 999), g)):
        lines.append(f"### {titles.get(gid, gid)}")
        lines.append("")
        for members, text in groups[gid]:
            head = members[0]
            title = " / ".join(one_line(m.get("title")) for m in members)
            lines.append(f"- **{type_prefix(head)}{md_escape_heading(title)}**")
            lines.append("")
            body = text if text is not None else plain(head.get("notes"))
            if len(members) > 1 and text is None:
                body = "\n\n".join(plain(m.get("notes")) for m in members)
            lines.extend(render_item_body(head, body))
            eids = {m.get("epic") for m in members if m.get("epic")}
            for eid in sorted(e for e in eids if e in epics):
                t, done, total = epics[eid]
                lines.append(f"  _Part of **{t}** — {done}/{total} complete._")
            credits = sorted({PUB.player_label(m) for m in members if PUB.player_label(m)})
            if credits:
                lines.append(f"  _Reported by {', '.join(credits)}._")
            lines.append("")
    return lines


def render_testers(ideas: list[dict], doc: dict, flavored) -> list[str]:
    """Only what still has an open UAT check, with who can run each check."""
    vis = [i for i in visible(ideas) if GEN.open_uat_steps(i)]
    if not vis:
        return ["_Everything in this range has already been validated._", ""]

    lines = []
    for members, text in bullets_for(vis, flavored):
        head = members[0]
        title = " / ".join(one_line(m.get("title")) for m in members)
        lines.append(f"### {type_prefix(head)}{md_escape_heading(title)}")
        lines.append("")
        body = text if text is not None else plain(head.get("notes"))
        if len(members) > 1 and text is None:
            body = "\n\n".join(plain(m.get("notes")) for m in members)
        for ln in (body or "").split("\n"):
            lines.append(ln.rstrip())
        lines.append("")
        lines.append("**Please check:**")
        lines.append("")
        for m in members:
            for step in GEN.open_uat_steps(m):
                who = (step.get("tester") or "").strip()
                txt = one_line(step.get("step"))
                lines.append(f"- {txt}" + (f"  _({who})_" if who else ""))
        lines.append("")
    return lines


def render_admin(ideas: list[dict], doc: dict, commits, claimed: set[str]) -> list[str]:
    lines = []
    hidden = [i for i in ideas if i.get("hidden")]
    if hidden:
        lines.append("### Hidden items in this range (never published)")
        lines.append("")
        for i in sorted(hidden, key=sort_key, reverse=True):
            lines.append(f"- `{i['id']}` — {one_line(i.get('title'))} "
                         f"[{i.get('status')}]")
        lines.append("")

    outstanding = []
    for i in sorted(ideas, key=sort_key, reverse=True):
        steps = GEN.open_steps(i, ("toolset", "admin"))
        if steps:
            outstanding.append((i, steps))
    if outstanding:
        lines.append("### Open toolset / admin steps")
        lines.append("")
        for i, steps in outstanding:
            lines.append(f"- `{i['id']}`")
            for s in steps:
                flag = " **BLOCKER**" if s.get("blocker") else ""
                lines.append(f"  - ({GEN.step_kind(s)}){flag} {one_line(s.get('step'))}")
        lines.append("")

    unattributed = [c for c in commits
                    if c["sha"] not in claimed and not NOISE_RE.match(c["subject"])]
    lines.append(f"### Unattributed commits ({len(unattributed)})")
    lines.append("")
    lines.append("_In the range, claimed by no roadmap item, and not routine "
                 "wiki/roadmap bookkeeping. Each one either needs a roadmap "
                 "item or is genuinely invisible to players._")
    lines.append("")
    if unattributed:
        for c in unattributed:
            lines.append(f"- `{c['short']}` {c['date']} — {c['subject']}")
    else:
        lines.append("- (none)")
    lines.append("")
    return lines


def render(args, base, prov, head, commits, ideas, claimed, doc, flavored) -> str:
    today = _dt.date.today().isoformat()
    wiki = season_env("SEASON_WIKI_URL")
    host = season_env("SEASON_CONNECT_HOST")
    num = season_env("SEASON_NUM")
    vis = visible(ideas)

    L: list[str] = []
    if args.audience == "testers":
        L.append(f"# Test realm — what's new and what needs testing ({today})")
        L.append("")
        L.append(f"These changes are live on the **test realm** right now, ahead of "
                 f"Season {num}. Everything below still needs someone to confirm it "
                 f"works.")
        if host or wiki:
            L.append("")
            bits = []
            if host:
                bits.append(f"Connect: `{host}`")
            if wiki:
                bits.append(f"Wiki: {wiki}")
            L.append(" · ".join(bits))
    elif args.audience == "players":
        L.append(f"# Season {num} update — what's new ({today})")
        L.append("")
        L.append("Everything below is now live.")
    else:
        L.append(f"# Dev → Season {num}: release-note working copy ({today})")

    L.append("")
    L.append(f"<!-- range {base[:11]}..{head[:11]} · {len(commits)} commits · "
             f"{len(vis)} items · base from {prov}"
             f"{' · flavored' if flavored else ''} -->")
    L.append("")

    if args.audience == "testers":
        L.extend(render_testers(ideas, doc, flavored))
    elif args.audience == "players":
        L.extend(render_players(ideas, doc, flavored))
    else:
        L.append("## What's new (player-facing)")
        L.append("")
        L.extend(render_players(ideas, doc, flavored))
        L.append("## Still needs testing")
        L.append("")
        L.extend(render_testers(ideas, doc, flavored))
        L.append("## Admin")
        L.append("")
        L.extend(render_admin(ideas, doc, commits, claimed))

    while L and not L[-1].strip():
        L.pop()
    return "\n".join(L) + "\n"


# --------------------------------------------------------------------- cli --

def main() -> int:
    ap = argparse.ArgumentParser(
        description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--audience", choices=("testers", "players", "admin"),
                    default="admin", help="who the notes are for (default: admin)")
    ap.add_argument("--target", default=str(DEFAULT_TARGET),
                    help="the season repo to diff against (default: ../nwn_homers_lotr_s2)")
    ap.add_argument("--since", help="baseline ref, overriding auto-detection")
    ap.add_argument("--flavor", action="store_true",
                    help="rewrite the notes and merge related items via the LAN model")
    ap.add_argument("--regen-flavor", action="store_true",
                    help="re-run the flavor pass even if a sidecar exists")
    ap.add_argument("--model", default="default",
                    help="which model does the --flavor rewrite: a bin/llm/config.py "
                         "alias (default, fast, best) or a literal Ollama tag. "
                         "--list-models shows what the box actually has.")
    ap.add_argument("--list-models", action="store_true",
                    help="list the models the LLM box is serving, and exit")
    ap.add_argument("--out", help="write here instead of stdout")
    ap.add_argument("--force", action="store_true",
                    help="run outside the dev realm (commit hashes may not resolve)")
    args = ap.parse_args()

    if args.list_models:
        for name, source in available_models():
            print(f"{name}\t{source}")
        return 0

    role = GEN.season_role()
    if role and role != "dev" and not args.force:
        print(f"error: this repo is SEASON_ROLE={role}, not dev. Roadmap `commit:` "
              f"hashes only resolve in the dev repo — run it there, or --force.",
              file=sys.stderr)
        return 1

    base, prov = resolve_base(Path(args.target).expanduser(), args.since)
    head = git("rev-parse", "HEAD").strip()
    commits = commits_in_range(base, head)

    doc = yaml.load(PUB.YAML_PATH.read_text(encoding="utf-8"), Loader=_YamlLoader) or {}
    all_ideas = doc.get("ideas") or []
    GEN.resolve_dates(all_ideas)
    ideas, claimed = match_ideas(all_ideas, commits)

    if not commits:
        print(f"[warn] {base[:11]}..HEAD is empty — the diff is already closed. "
              f"Pass --since <the previous base> to re-generate past notes.",
              file=sys.stderr)

    flavored = None
    if args.flavor:
        pool = visible(ideas)
        if args.audience == "testers":
            pool = [i for i in pool if GEN.open_uat_steps(i)]
        flavored = run_flavor(pool, base, head, args.regen_flavor, args.model)

    text = render(args, base, prov, head, commits, ideas, claimed, doc, flavored)
    if args.out:
        Path(args.out).write_text(text, encoding="utf-8")
        print(f"wrote {args.out} ({len(commits)} commits, {len(visible(ideas))} items, "
              f"base {base[:11]} from {prov})", file=sys.stderr)
    else:
        sys.stdout.write(text)
    return 0


if __name__ == "__main__":
    sys.exit(main())
