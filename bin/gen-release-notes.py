#!/usr/bin/env python3
"""Release notes for the commits that are in the dev realm but not yet in a season.

Two audiences, one dataset:

    --audience testers   what just landed on the test realm and what still needs
                         checking — published while the diff is open
    --audience players   a Discord post: one line per change, each linked to its
                         forum thread — published when bin/season-promote.sh
                         closes the diff
    --audience admin     both, plus hidden items, plus the commits no roadmap
                         item claimed (the "nothing silently vanished" check)

## The players audience is a Discord post, not a document

The backlog is mirrored into a Discord forum by nwnbot, and an idea that has been
linked to its thread carries `discord: {thread_id, channel_id, url}`. That thread
is where the detail lives now — the screenshots, the report, the back and forth —
so the announcement does not restate the note. It is the shortest thing that still
says what shipped: a bold group heading, then one line per item,

    <emoji> [title](thread url) — reporter

with the title left plain when that idea has no thread yet. No note bodies, no
epic progress, no commit counts or hashes, and no `<!-- range -->` comment (Discord
renders an HTML comment as literal text). It is meant to be copied out of the
roadmap editor and pasted straight into a message.

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
import unicodedata
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


# The players audience is a Discord post, where a marker the eye catches beats
# the words "Bug fixed: ". This is only the FALLBACK -- --flavor lets the local
# model pick up to three emojis that actually depict the change. PUB.TYPE_PREFIX
# is untouched: it is still what the in-game sign and the testers notes use.
TYPE_EMOJI = {"Defect": "🐛", "Enhancement": "✨", "Exploit": "🛡️"}
DEFAULT_EMOJI = "🔧"


def type_emoji(idea: dict) -> str:
    return TYPE_EMOJI.get(idea.get("type"), DEFAULT_EMOJI)


def discord_url(idea: dict) -> str:
    d = idea.get("discord")
    return str(d.get("url") or "") if isinstance(d, dict) else ""


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
FLAVOR_EMOJI_SYSTEM = (
    "You label release notes for a Lord of the Rings themed Neverwinter Nights "
    "persistent world. You are given a list of changes that shipped in one "
    "update, each with an id, a title, a type and a short note.\n\n"
    "For every id, choose one to three emojis that depict that change — what it "
    "is about (a forge, a boss, a sword, a map, a bug) and, where it fits, "
    "whether it is a fix or something new. Prefer one; use three only when they "
    "really say more than one does.\n\n"
    "Answer with emoji characters only. No words, no punctuation, no spaces "
    "between them, no skin tones. Every id you were given must appear exactly "
    "once. Never invent an id."
)

FLAVOR_EMOJI_SCHEMA = {
    "type": "object",
    "properties": {
        "items": {
            "type": "array",
            "items": {
                "type": "object",
                "properties": {
                    "id": {"type": "string"},
                    "emoji": {"type": "string"},
                },
                "required": ["id", "emoji"],
            },
        }
    },
    "required": ["items"],
}
FLAVOR_PROMPT_VERSION = 3
# A roadmap note runs to several paragraphs; the model only needs enough to
# judge relatedness and write a sentence, and the deterministic fallback still
# renders the note in full. Keeping the payload small is what keeps a wide
# range (a whole season's worth of items) inside one context window.
FLAVOR_NOTE_CHARS = 900
# Picking an emoji needs the gist, not the note. A quarter of the prose budget
# keeps a whole season of items inside one context window.
FLAVOR_EMOJI_NOTE_CHARS = 200
# At most three, and only the emoji itself survives: the model is asked for
# emoji only, but a 12B model will hand back "Bug fix 🐛" often enough to matter.
FLAVOR_EMOJI_MAX = 3
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


def emoji_input(ideas: list[dict]) -> list[dict]:
    """What the emoji pass sends — same rule as flavor_input: no server.env."""
    return [{
        "id": i["id"],
        "title": one_line(i.get("title")),
        "type": i.get("type") or "",
        "group": i.get("group") or "",
        "note": _clip(plain(i.get("notes")), FLAVOR_EMOJI_NOTE_CHARS),
    } for i in sorted(ideas, key=lambda i: i["id"])]


def available_models() -> list[dict]:
    """Rows for the model picker: {name, label, hint, source}. Never raises.

    The registry rows always come back, so the roadmap editor's dropdown offers
    every model even when the box answers nothing -- which is its normal state,
    since the router only loads a model once a request names one. `source` says
    how much is known about a row:

      registry  a `bin/llm/config.py` name the box did not confirm
      served    the box listed it
      extra     the box serves it and config.py has never heard of it
      error     not a model at all: why the box could not be asked

    `default` is deliberately not offered. It is an alias for whichever model
    config.py points at, and offering both it and its target invites picking the
    same model twice under two names -- and so under two cache keys.
    """
    served: list[str] = []
    error = ""
    try:
        from llm.client import Client
        served = Client().available_models()
    except Exception as exc:                              # noqa: BLE001
        error = str(exc)

    registry = _llm_config_models()
    targets = set(registry.values())
    out: list[dict] = []
    for name, target in registry.items():
        if name == "default" and target in registry:
            continue
        label, hint = _model_info(name)
        out.append({"name": name, "label": label, "hint": hint,
                    "source": "served" if name in served else "registry"})
    for tag in served:
        if tag not in registry and tag not in targets:
            out.append({"name": tag, "label": tag, "source": "extra",
                        "hint": "served by the box but not in bin/llm/config.py"})
    if error:
        out.append({"name": f"(the LLM box did not answer: {error})",
                    "label": "", "hint": "", "source": "error"})
    return out


def _llm_config_models() -> dict[str, str]:
    try:
        from llm import config
        return dict(config.MODELS)
    except Exception:                                     # noqa: BLE001
        return {"default": "default"}


def _model_info(name: str) -> tuple[str, str]:
    """(label, hint) for the picker -- the bare name when config says nothing."""
    try:
        from llm import config
        label, hint = config.MODEL_INFO[name]
        return label, hint
    except Exception:                                     # noqa: BLE001
        return name, ""


def flavor_ctx(user: str, system: str = FLAVOR_SYSTEM) -> int:
    """A context window big enough for this prompt.

    Ollama defaults to 4096, which a range of any size overflows with a bare
    HTTP 400 — sized here rather than fixed so a wide --since still works.
    """
    approx = (len(user) + len(system)) // 3 + 1500
    return max(FLAVOR_CTX_MIN, min(FLAVOR_CTX_MAX, 1 << (approx - 1).bit_length()))


def flavor_fingerprint(payload: list[dict], model: str, mode: str = "prose") -> str:
    """Identity of a flavor pass: these items, put through this mode by this model.

    The model is in here because switching models must not silently return the
    previous model's cached text -- the whole point of being able to try a new
    one is seeing what it writes. The mode is in here because the prose pass and
    the emoji pass run over the same range and the same items, and a sidecar
    from one must never be read back as the other.
    """
    blob = json.dumps([mode, model, payload], sort_keys=True, ensure_ascii=False)
    return hashlib.sha256(blob.encode("utf-8")).hexdigest()[:16]


def flavor_path(base: str, head: str, fingerprint: str) -> Path:
    """One sidecar per (range, item set).

    The fingerprint is in the NAME, not just the body, because --audience
    testers flavors a smaller pool than --audience players over the same range.
    Keyed on the range alone they would evict each other on every switch.
    """
    return FLAVOR_DIR / f"{base[:11]}-{head[:11]}.{fingerprint}.flavor.json"


def load_flavor(path: Path, key: str = "bullets") -> list[dict] | None:
    """A cached flavor pass for this exact item set, if one was written."""
    try:
        doc = json.loads(path.read_text(encoding="utf-8"))
    except (OSError, ValueError):
        return None
    return doc.get(key)


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


def ask_model(model: str, system: str, user: str, schema: dict,
              regen: bool) -> tuple[dict | None, str]:
    """(answer, model name) from the LAN box, or (None, "") with a warning.

    Every failure here -- no client, box asleep, bad request -- is a warning and
    a None, never an exception: --flavor is an embellishment, and must never be
    the difference between output and no output.
    """
    try:
        from llm.client import Client, LLMError, LLMUnavailable
    except ImportError as exc:                        # pragma: no cover
        print(f"[warn] --flavor: cannot import the LLM client ({exc}); "
              f"writing the deterministic notes instead", file=sys.stderr)
        return None, ""

    client = Client(model)
    ok, msg = client.health()
    if not ok:
        print(f"[warn] --flavor: the LLM box is unreachable ({msg}); "
              f"writing the deterministic notes instead", file=sys.stderr)
        return None, ""

    try:
        raw = client.chat(system, user, schema,
                          prompt_version=FLAVOR_PROMPT_VERSION,
                          temperature=0.2, num_ctx=flavor_ctx(user, system),
                          nonce=None if not regen else int(_dt.datetime.now().timestamp()))
    except (LLMError, LLMUnavailable) as exc:
        print(f"[warn] --flavor: {exc}; writing the deterministic notes instead",
              file=sys.stderr)
        return None, ""
    return raw, client.short_name


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

    user = ("Changes in this update:\n\n"
            + json.dumps(payload, indent=2, ensure_ascii=False))
    raw, short_name = ask_model(model, FLAVOR_SYSTEM, user, FLAVOR_SCHEMA, regen)
    if raw is None:
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
         "model": short_name, "model_arg": model,
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


# ------------------------------------------------------- flavor (emoji) --
#
# The players audience has no prose left to rewrite, so --flavor does the one
# judgement call that is left there: which emoji depicts this change. Same
# cache, same repair-don't-reject rule, same "a sleeping box costs you nothing".

# A ZWJ or a variation selector belongs to the emoji before it (a flag, a
# profession, a family); so does a skin-tone modifier, which is then dropped
# with its base if the model ignored the instruction not to use one.
_EMOJI_JOINERS = {0x200D, 0xFE0F, 0xFE0E}


def emoji_only(text: str) -> str:
    """The first FLAVOR_EMOJI_MAX emoji in `text`, with everything else dropped.

    The model is asked for emoji alone and mostly complies, but "Bug fix 🐛" and
    a comma-separated list both turn up, and a stray word in a Discord post is
    worse than no emoji at all.
    """
    out: list[str] = []
    for ch in str(text or ""):
        cp = ord(ch)
        if cp in _EMOJI_JOINERS or 0x1F3FB <= cp <= 0x1F3FF:
            if out:
                out[-1] += ch
            continue
        if cp < 0x2000 or unicodedata.category(ch) not in ("So", "Sk"):
            continue                      # words, digits, punctuation, spaces
        if out and out[-1].endswith("\u200d"):
            out[-1] += ch                 # part of the ZWJ sequence before it
        else:
            out.append(ch)
    return "".join(out[:FLAVOR_EMOJI_MAX])


def repair_emoji(items, ideas: list[dict]) -> tuple[dict[str, str], list[str]]:
    """{id: emoji} the renderer can trust, plus what had to be repaired.

    Nothing is rejected wholesale: an id the model forgot, invented or labelled
    with words simply has no entry, and type_emoji() fills it in. So the worst
    case of a bad answer is the deterministic post.
    """
    valid = {i["id"] for i in ideas}
    warnings: list[str] = []
    out: dict[str, str] = {}
    if not isinstance(items, list) or not items:
        return {}, ["no emoji returned"]

    for it in items:
        if not isinstance(it, dict):
            warnings.append("dropped a malformed entry")
            continue
        iid = str(it.get("id") or "")
        if iid not in valid:
            warnings.append(f"dropped invented id {iid!r}")
            continue
        if iid in out:
            warnings.append(f"dropped repeated id {iid!r}")
            continue
        chosen = emoji_only(it.get("emoji"))
        if not chosen:
            warnings.append(f"id {iid!r} came back without a usable emoji")
            continue
        out[iid] = chosen

    missing = sorted(valid - set(out))
    if missing:
        warnings.append(f"{len(missing)} item(s) got no emoji and fall back to "
                        f"their type: {', '.join(missing[:5])}"
                        + (" …" if len(missing) > 5 else ""))
    return out, warnings


def run_emoji_flavor(ideas: list[dict], base: str, head: str, regen: bool,
                     model: str = "default") -> dict[str, str]:
    """{id: emoji} for the players post, cached to its own sidecar."""
    if not ideas:
        return {}
    payload = emoji_input(ideas)
    fp = flavor_fingerprint(payload, model, mode="emoji")
    path = flavor_path(base, head, fp)

    if not regen:
        cached = load_flavor(path, "items")
        if cached is not None:
            fixed, _ = repair_emoji(cached, ideas)
            return fixed

    user = ("Changes in this update:\n\n"
            + json.dumps(payload, indent=2, ensure_ascii=False))
    raw, short_name = ask_model(model, FLAVOR_EMOJI_SYSTEM, user,
                                FLAVOR_EMOJI_SCHEMA, regen)
    if raw is None:
        return {}

    items = (raw or {}).get("items") if isinstance(raw, dict) else None
    chosen, warnings = repair_emoji(items, ideas)
    for w in warnings:
        print(f"[warn] --flavor: {w}", file=sys.stderr)
    if not chosen:
        print("[warn] --flavor: no emoji survived; the post falls back to one "
              "per type", file=sys.stderr)
        return {}

    FLAVOR_DIR.mkdir(parents=True, exist_ok=True)
    path.write_text(json.dumps(
        {"base": base, "head": head, "fingerprint": fp, "mode": "emoji",
         "prompt_version": FLAVOR_PROMPT_VERSION,
         "model": short_name, "model_arg": model,
         "generated": _dt.date.today().isoformat(),
         "warnings": warnings,
         "_comment": ("Hand-edit `items` freely: `emoji` is what renders before "
                      "that item's line, at most three, and an id with none "
                      "falls back to one emoji per type. Rerun with "
                      "--regen-flavor to throw this away and re-roll."),
         "items": [{"id": k, "emoji": v} for k, v in sorted(chosen.items())]},
        indent=2, ensure_ascii=False) + "\n", encoding="utf-8")
    print(f"[info] --flavor: emoji for {len(chosen)}/{len(ideas)} item(s), "
          f"cached in {path.relative_to(REPO)}", file=sys.stderr)
    return chosen


# ------------------------------------------------------------- render --

def md_escape_heading(s: str) -> str:
    return s.replace("\n", " ").strip()


def group_titles(doc: dict) -> dict:
    return {g["id"]: plain(g.get("title") or g["id"]) for g in (doc.get("groups") or [])}


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


def player_line(idea: dict, emoji: dict[str, str]) -> str:
    """One item as one Discord line: `<emoji> [title](thread) — reporter`.

    The thread carries the detail, so nothing else from the idea belongs here.
    An item nobody has linked to a thread yet still appears — unlinked rather
    than unannounced.
    """
    title = one_line(idea.get("title")).replace("[", "(").replace("]", ")")
    url = discord_url(idea)
    label = f"[{title}]({url})" if url else title
    who = PUB.player_label(idea)
    return (f"{emoji.get(idea['id']) or type_emoji(idea)} {label}"
            + (f" — {who}" if who else ""))


def render_players(ideas: list[dict], doc: dict, emoji: dict[str, str]) -> list[str]:
    """The update announcement as a Discord post: links, grouped by category.

    Deliberately NOT the roadmap note. Every shipped idea that has been linked
    to its Discord forum thread points at it, and that thread is where a player
    reads what changed and argues about it — so restating the note here would
    only be a second, staler copy of the thread's first post. What is left is
    the shortest thing that still says what shipped.
    """
    titles = group_titles(doc)
    vis = visible(ideas)
    if not vis:
        return ["_Nothing player-facing in this range._", ""]

    groups: dict[str, list] = {}
    for idea in sorted(vis, key=sort_key, reverse=True):
        groups.setdefault(idea.get("group") or "other", []).append(idea)

    order = {g["id"]: g.get("order", 999) for g in (doc.get("groups") or [])}
    lines = []
    for gid in sorted(groups, key=lambda g: (order.get(g, 999), g)):
        lines.append(f"**{md_escape_heading(titles.get(gid, gid))}**")
        lines.extend(player_line(i, emoji) for i in groups[gid])
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


def render(args, base, prov, head, commits, ideas, claimed, doc, flavored,
           emoji: dict[str, str] | None = None) -> str:
    today = _dt.date.today().isoformat()
    emoji = emoji or {}
    wiki = season_env("SEASON_WIKI_URL")
    # The players post announces the LIVE season, so it must not advertise the
    # dev realm's wiki -- which is what SEASON_WIKI_URL is in this repo.
    live_wiki = season_env("SEASON_LIVE_WIKI_URL") or wiki
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
        # A Discord post, so: no HTML comment (Discord renders it as literal
        # text), no range, no commit count, no preamble anyone has to read.
        L.append(f"## Season {num} update — {today}")
        L.append("")
        L.extend(render_players(ideas, doc, emoji))
        L.append("_Click a change to read its thread._"
                 + (f" · Wiki: {live_wiki}" if live_wiki else ""))
        while L and not L[-1].strip():
            L.pop()
        return "\n".join(L) + "\n"
    else:
        L.append(f"# Dev → Season {num}: release-note working copy ({today})")

    L.append("")
    L.append(f"<!-- range {base[:11]}..{head[:11]} · {len(commits)} commits · "
             f"{len(vis)} items · base from {prov}"
             f"{' · flavored' if flavored else ''} -->")
    L.append("")

    if args.audience == "testers":
        L.extend(render_testers(ideas, doc, flavored))
    else:
        L.append("## What's new (player-facing)")
        L.append("")
        L.extend(render_players(ideas, doc, emoji))
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
                    help="ask the LAN model to help: rewrite and merge the notes "
                         "(testers/admin), pick each item's emoji (players)")
    ap.add_argument("--regen-flavor", action="store_true",
                    help="re-run the flavor pass even if a sidecar exists")
    ap.add_argument("--model", default="default",
                    help="which model does the --flavor rewrite: a name the LLM "
                         "box serves (qwen36, deepseek9b, deepseek) or the "
                         "`default` alias. --list-models shows the live list.")
    ap.add_argument("--list-models", action="store_true",
                    help="list the models the LLM box will serve, and exit")
    ap.add_argument("--out", help="write here instead of stdout")
    ap.add_argument("--force", action="store_true",
                    help="run outside the dev realm (commit hashes may not resolve)")
    args = ap.parse_args()

    if args.list_models:
        for row in available_models():
            print(f"{row['name']}\t{row['source']}\t{row.get('hint') or ''}")
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

    # Two different jobs share one flag. The prose pass rewrites and merges the
    # notes the testers/admin documents render; the players post has no prose
    # left to rewrite, so there the model only picks the emoji. The admin
    # audience contains both documents, so it runs both (each cached).
    flavored, emoji = None, {}
    if args.flavor:
        pool = visible(ideas)
        if args.audience != "players":
            prose_pool = ([i for i in pool if GEN.open_uat_steps(i)]
                          if args.audience == "testers" else pool)
            flavored = run_flavor(prose_pool, base, head, args.regen_flavor,
                                  args.model)
        if args.audience != "testers":
            emoji = run_emoji_flavor(pool, base, head, args.regen_flavor,
                                     args.model)

    text = render(args, base, prov, head, commits, ideas, claimed, doc, flavored,
                  emoji)
    if args.out:
        Path(args.out).write_text(text, encoding="utf-8")
        print(f"wrote {args.out} ({len(commits)} commits, {len(visible(ideas))} items, "
              f"base {base[:11]} from {prov})", file=sys.stderr)
    else:
        sys.stdout.write(text)
    return 0


if __name__ == "__main__":
    sys.exit(main())
