#!/usr/bin/env python3
"""The PUBLIC projection of roadmap.yaml — what a logged-out visitor may see.

`https://roadmap.homerslotr.com/` is open to anyone: a player who follows a
Discord link to one idea resolves to the anonymous `public` role
(roadmap_auth.ANON_ROLE) and is served /api/public-data, which is built here.

Why this is a separate module and a separate route rather than a filter on
/api/data:

  * /api/data hands the browser the WHOLE document — hidden items, impl_notes,
    manual_steps, uat_credits, merit_awarded, the commit hash. Hiding those in
    the page would be decoration, not privacy, so the payload itself has to be
    different.
  * The projection is a WHITELIST (PUBLIC_IDEA_FIELDS). A field added to
    roadmap-editor.py's FIELD_ORDER later is private by default and stays
    private until somebody deliberately adds it here. A blacklist would leak
    every field nobody remembered to think about — which, for a file that grows
    a field every few weeks, is only a matter of time.
  * It is importable (roadmap-editor.py cannot be, its name is hyphenated), so
    bin/roadmap-auth-selftest.py can assert the projection against the real
    roadmap.yaml without standing a server up.

Which IDEAS are public is deliberately NOT decided here: it is
gen-roadmap.py's publishable(), the same function the wiki page and the
in-game Recent Updates sign are built from. One definition of "public" for all
three, so nothing can be public on one surface and private on another.
"""
from __future__ import annotations

import importlib.util
from pathlib import Path

REPO = Path(__file__).resolve().parent.parent
GEN_PATH = REPO / "bin" / "gen-roadmap.py"

#: Every field of an idea a logged-out visitor may see. Whitelist — see above.
#:
#: Redacted by omission, and each for its own reason: `hidden`/`triage` (the
#: items are gone entirely, so the flags have nothing to say), `commit`,
#: `impl_notes`, `design_questions`, `manual_steps`, `uat_credits`, `comments`
#: (the builder's internal record and the tester lane), `merit_awarded` (what
#: the server owes a player), `notes_h`/`impl_notes_h` (editor box heights),
#: `dupe_of`/`dupe_candidates`/`depends_on` (internal bookkeeping).
PUBLIC_IDEA_FIELDS: frozenset[str] = frozenset((
    "id", "title", "group", "epic", "status", "type", "player", "date",
    # The player-facing release note. This is the one rich-text body written
    # to be read by players -- roadmap-editor.py's own form labels it "shown on
    # the public roadmap", and gen-roadmap.py already publishes it.
    "notes",
    # Narrowed to {url} by public_idea(): thread_id and channel_id are Discord
    # plumbing the browser has no use for.
    "discord",
))


def load_gen():
    """Import gen-roadmap.py (hyphenated, so it cannot be imported by name)."""
    spec = importlib.util.spec_from_file_location("gen_roadmap", GEN_PATH)
    mod = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(mod)
    return mod


def public_idea(idea: dict) -> dict:
    """One idea, reduced to PUBLIC_IDEA_FIELDS."""
    out = {k: v for k, v in idea.items() if k in PUBLIC_IDEA_FIELDS}
    # merge_dupes() is not run for this view (a duplicate row is just another
    # card here), so `_requesters` and friends never appear -- but any private
    # key an upstream pass might hang on the dict is dropped by the whitelist
    # above regardless, which is the point of writing it that way.
    d = out.get("discord")
    if isinstance(d, dict):
        url = str(d.get("url") or "")
        if url:
            out["discord"] = {"url": url}
        else:
            out.pop("discord")
    elif d is not None:
        out.pop("discord")
    return out


def public_ideas(doc: dict, gen=None) -> list[dict]:
    """The ideas a logged-out visitor may see, already projected.

    `gen` lets a caller that has already imported gen-roadmap.py (the editor
    has) pass it in rather than paying for a second exec of the module.
    """
    gen = gen or load_gen()
    # publishable() drops `hidden` AND `triage`, and warns about a dupe_of
    # pointing into what it dropped. It mutates the ideas it is given, so hand
    # it copies -- the editor's read_yaml() cache would otherwise be poisoned.
    ideas = [dict(i) for i in (doc.get("ideas") or []) if isinstance(i, dict)]
    return [public_idea(i) for i in gen.publishable(ideas)]


def public_vocab(doc: dict, ideas: list[dict], gen=None) -> dict:
    """The filter-bar vocabularies, derived from the PROJECTED ideas.

    Never from the raw document. roadmap-editor.py's vocab() emits a `dupes`
    list of {id, title} across every idea in the file and a player roster read
    from the file's own `players:` block; both would carry the titles of hidden
    items and the names of people who have reported nothing public straight
    into this payload. Groups and epics are likewise narrowed to the ones some
    public idea actually belongs to -- an epic whose every child is hidden is
    unreleased work, and its title and notes are not public either.
    """
    gen = gen or load_gen()
    used_groups = {i.get("group") for i in ideas}
    used_epics = {i.get("epic") for i in ideas if i.get("epic")}
    groups = [{"id": g["id"], "title": g["title"], "order": g.get("order")}
              for g in (doc.get("groups") or []) if g.get("id") in used_groups]
    epics = [{"id": e["id"], "title": e.get("title", ""), "group": e.get("group"),
              "notes": e.get("notes")}
             for e in (doc.get("epics") or []) if e.get("id") in used_epics]
    players = sorted({i["player"] for i in ideas if i.get("player")},
                     key=str.lower)
    return {
        "groups": groups,
        "epics": epics,
        "players": players,
        "statuses": [{"id": k, "label": v["label"]} for k, v in gen.STATUS.items()],
        "types": [{"id": k, "label": v["label"]} for k, v in gen.TYPES.items()],
        # Present and empty rather than absent: the page's pickers read these
        # by name, and an undefined is a different bug from an empty list.
        "ids": [], "dupes": [], "today": "",
    }


def public_payload(doc: dict, version: str, me: dict, gen=None) -> dict:
    """The whole /api/public-data body."""
    gen = gen or load_gen()
    ideas = public_ideas(doc, gen)
    return {"ideas": ideas, "vocab": public_vocab(doc, ideas, gen),
            "version": version, "me": me,
            # No base_hashes / base_vocab: those are the save-merge baseline,
            # and this view can never save. No `environments` either -- which
            # realm an idea's code is on is the promotion state of unreleased
            # work.
            "public": True}


if __name__ == "__main__":   # tiny CLI: eyeball the projection
    import json
    import sys

    import yaml  # noqa: F401  (only needed for this path)

    text = (REPO / "roadmap.yaml").read_text(encoding="utf-8")
    document = yaml.safe_load(text) or {}
    json.dump(public_payload(document, "", {}), sys.stdout, indent=2)
