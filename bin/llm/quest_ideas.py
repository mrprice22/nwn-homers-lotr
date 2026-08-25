#!/usr/bin/env python3
"""Propose new quest lines as hidden roadmap entries.

    python3 bin/llm/quest_ideas.py --count 5              # propose, print, write nothing
    python3 bin/llm/quest_ideas.py --count 5 --apply      # file them as hidden ideas
    python3 bin/llm/quest_ideas.py --theme "Dwarves of Erebor" --count 3

Unlike every other task in this harness, the output is not a field in a
blueprint -- it is a **proposal**, and it lands in `roadmap.yaml` as an idea with
`hidden: true`. That is what makes generating them safe: a hidden idea is off the
public roadmap page and off the in-game Recent Updates sign, so a bad proposal
costs the admin one click to delete and nothing else. (This is the 2026-08-23
rule change: agents may mint ideas freely, but only hidden ones.)

It never writes NWScript, a journal entry, an area or a blueprint. A quest line
here is a **design proposal in prose** for a human to accept, reshape or bin. The
local model has no way to check that a script function exists or that an area is
reachable, and the roadmap is exactly the right place for an idea that has not
been checked yet.

Grounding matters more here than anywhere else in the harness. The prompt is
given the module's real journal quests, its real area names and the quest ideas
already in the backlog, so proposals reference places that exist and do not
re-file something already on the list. Every proposal is then run through the
same duplicate check as `roadmap_dupe.py` before it is offered.
"""
from __future__ import annotations

import argparse
import importlib.util
import json
import random
import re
import sys
from pathlib import Path

if __package__ in (None, ""):
    import pathlib as _pathlib
    _p = str(_pathlib.Path(__file__).resolve().parents[1])
    if _p not in sys.path:
        sys.path.insert(0, _p)

import yaml

from llm import config, gff
from llm.client import Client, LLMUnavailable

GROUP = "quests-areas"
PLAYER = "HomelessSon (Server Admin)"
STATUS = "later"
# How far apart consecutive quest areas may be, in area transitions. A quest
# line is a journey a player actually makes; twelve loading screens between two
# steps means the quest is not the one the model thought it was writing.
MAX_HOPS = 12

# Quest shapes, rotated one per proposal. This is not decoration.
#
# On 2026-08-14 the admin pulled back 43 shipped quest-line items with the
# complaint that they were "structurally identical clones of each other -- every
# class line is oath -> fetch shard -> reforge with the nouns swapped". Asked for
# quest lines with no further steering, this model produces exactly that: the
# first three proposals it ever made were all "speak to the giver, travel, pick
# the thing up, bring it back", with a pack, some crates and a herb in the object
# slot. Each one reads fine alone. Together they are the rejected pattern.
#
# So the shape is assigned, not chosen -- one per proposal, and fetch-and-return
# is deliberately absent from the list.
SHAPES = (
    "An INVESTIGATION. Something has already happened and the player works out "
    "what. At least one step is finding out, not fetching. It can end without "
    "combat.",
    "A CHOICE WITH A COST. Two people want incompatible things and both have a "
    "case. The player picks one and the other outcome actually happens. Say in "
    "the premise what is lost either way.",
    "A DEFENCE. Something must be held, hidden or kept working while under "
    "pressure. The player is reacting, not collecting.",
    "SOMEBODY IS LYING. The quest giver's account is wrong -- self-serving, "
    "mistaken, or frightened. The middle steps are where that surfaces.",
    "A RIVALRY. Two named parties are already in conflict and the player is "
    "leverage. Their goals do not include the player's convenience.",
    "A RESCUE THAT GOES WRONG. What the player was sent to do turns out to be "
    "the wrong thing, or too late, and the remaining steps deal with that.",
    "A NEGOTIATION. The obstacle is a person with their own interests, not a "
    "locked door or a monster. Violence is available and is the worse outcome.",
    "AN AFTERMATH. The dangerous part is over. The quest is about the mess it "
    "left and who pays for it.",
)

SCHEMA = {
    "type": "object",
    "properties": {
        "quests": {
            "type": "array",
            "items": {
                "type": "object",
                "properties": {
                    "id": {"type": "string"},
                    "title": {"type": "string"},
                    "premise": {"type": "string"},
                    "steps": {"type": "array", "items": {"type": "string"}},
                    "areas": {"type": "array", "items": {"type": "string"}},
                    "reward": {"type": "string"},
                    "confidence": {"type": "number"},
                },
                "required": ["id", "title", "premise", "steps", "areas", "reward",
                             "confidence"],
            },
        },
    },
    "required": ["quests"],
}

SYSTEM = """You propose quest lines for a Lord of the Rings themed Neverwinter Nights persistent world.

You are writing a DESIGN PROPOSAL for a human builder to read, not a script and
not a journal entry. Someone must be able to read yours and know what to build.

Rules:
1. Use only areas from the list you are given. Do not invent locations. If a
   quest wants somewhere that does not exist, choose a different quest.
2. Do not duplicate the existing quests or the backlog entries you are shown.
3. Three to six steps. Each step is one concrete thing a player does -- go
   somewhere, talk to someone, kill something, fetch something, choose something.
   "Experience the atmosphere" is not a step.
4. `id` is short, lowercase, hyphenated, and describes the quest: `barrow-wight-hoard`.
5. `title` is what a player would see. `premise` is two or three sentences of
   plain description: who wants what, and why the player is involved.
6. `reward` says what the player gets in a sentence. Do not give numbers, item
   names you invented, or amounts of gold.
7. Tolkien's register: small, grounded, human stakes. Not a world-ending threat
   every time. The best quests here are somebody's specific problem.
7b. DO NOT write a fetch-and-return quest. "Speak to someone, travel somewhere,
   pick a thing up, bring it back" is the single pattern this module already has
   too much of -- forty-three quest lines were withdrawn from it for being that
   same shape with the nouns swapped. Each proposal below is assigned a
   different shape and must follow the one it is given.
8. Plain ASCII punctuation. Use -- for a dash.
9. Keep the whole quest in one region. The areas you list must be plausibly
   walkable from one another -- a quest that sends a player from Rivendell to
   Ithilien is not one quest, it is a journey across the world.

`confidence` is 0.0 to 1.0: how buildable you think this is with what you were
shown. Be honest; a low score is useful information."""


def load_editor():
    spec = importlib.util.spec_from_file_location(
        "ed", config.REPO / "bin" / "roadmap-editor.py")
    mod = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(mod)
    return mod


def journal_quests() -> list[str]:
    path = config.UNPACKED / "module.jrl.json"
    if not path.exists():
        return []
    data = gff.load(path)
    out = []
    for cat in (data.get("Categories") or {}).get("value") or []:
        name = ((cat.get("Name") or {}).get("value") or {}).get("0", "").strip()
        # Some categories carry a bare string ref id rather than a title.
        if name and not name.isdigit():
            out.append(name)
    return out


def area_names() -> list[str]:
    path = config.MODULE_INDEX / "area_index.json"
    if path.exists():
        return [a["name"] for a in json.loads(path.read_text())["areas"]
                if not a.get("hidden") and a.get("name")]
    return sorted({gff.read_loc(gff.load(p), "Name")
                   for p in config.UNPACKED.glob("*.are.json")} - {""})


def area_graph() -> tuple[dict[str, set[str]], dict[str, str]]:
    """(adjacency by resref, name -> resref). Empty when the index is missing."""
    path = config.MODULE_INDEX / "area_graph.json"
    if not path.exists():
        return {}, {}
    areas = json.loads(path.read_text())["areas"]
    adjacency: dict[str, set[str]] = {}
    by_name: dict[str, str] = {}
    for resref, node in areas.items():
        by_name[(node.get("name") or "").lower()] = resref
        neighbours = {t["to"] for t in node.get("transitions") or [] if t.get("to")}
        adjacency.setdefault(resref, set()).update(neighbours)
        for other in neighbours:                 # treat transitions as two-way
            adjacency.setdefault(other, set()).add(resref)
    return adjacency, by_name


def hops(adjacency: dict[str, set[str]], start: str, goal: str, cap: int) -> int | None:
    """Shortest path length, or None if further than `cap` or unreachable."""
    if start == goal:
        return 0
    seen, frontier = {start}, [start]
    for distance in range(1, cap + 1):
        nxt = []
        for node in frontier:
            for neighbour in adjacency.get(node, ()):
                if neighbour in seen:
                    continue
                if neighbour == goal:
                    return distance
                seen.add(neighbour)
                nxt.append(neighbour)
        if not nxt:
            return None
        frontier = nxt
    return None


def backlog() -> list[dict]:
    data = yaml.safe_load((config.REPO / "roadmap.yaml").read_text())
    return data["ideas"]


def slug(text: str) -> str:
    return re.sub(r"-+", "-", re.sub(r"[^a-z0-9]+", "-", text.lower())).strip("-")[:48]


def propose(client: Client, count: int, theme: str, seed: int) -> list[dict]:
    quests = journal_quests()
    areas = area_names()
    ideas = backlog()
    quest_ideas = [i for i in ideas if i.get("group") == GROUP]

    # Sample rather than dump: 293 areas and 135 backlog rows is a wall of text
    # that makes the proposals worse, not better. A different sample per run also
    # keeps repeated runs from converging on the same corner of the map.
    rng = random.Random(seed)
    area_sample = rng.sample(areas, min(60, len(areas)))

    # One shape per proposal, sampled without replacement so a run of three
    # cannot draw the same shape three times.
    picked = rng.sample(SHAPES, min(count, len(SHAPES)))
    while len(picked) < count:
        picked.append(rng.choice(SHAPES))
    shapes = "\n\n".join(f"Quest {i + 1} must be: {s}" for i, s in enumerate(picked))

    user = (
        (f"Theme to work within: {theme}\n\n" if theme else "")
        + f"Propose {count} quest lines. Each has an assigned shape -- follow it.\n\n"
        + shapes + "\n\n"
        + "Areas that exist in the module (use only these):\n"
        + ", ".join(sorted(area_sample))
        + "\n\nQuests the module already has (do not repeat these):\n"
        + "\n".join(f"- {q}" for q in sorted(quests)[:70])
        + "\n\nQuest ideas already in the backlog (do not repeat these either):\n"
        + "\n".join(f"- {i.get('title', '')}" for i in quest_ideas[:70])
    )
    result = client.chat(SYSTEM, user, SCHEMA, prompt_version=1, temperature=0.95)
    proposals = (result or {}).get("quests", [])

    adjacency, by_name = area_graph()
    known_areas = {a.lower() for a in areas}
    known_ids = {i["id"] for i in ideas}
    known_titles = {(i.get("title") or "").lower() for i in ideas}

    for p in proposals:
        p["id"] = slug(p.get("id") or p.get("title", ""))
        warnings = []
        bad = [a for a in p.get("areas", []) if a.lower() not in known_areas]
        if bad:
            warnings.append("areas not in the module: " + ", ".join(bad[:3]))
        if p["id"] in known_ids:
            warnings.append(f"id '{p['id']}' already exists")
        if (p.get("title") or "").lower() in known_titles:
            warnings.append("title already in the backlog")
        if not 3 <= len(p.get("steps") or []) <= 6:
            warnings.append(f"{len(p.get('steps') or [])} steps (wanted 3-6)")

        # Existing-and-real is not enough. A proposal sent a player from a
        # healer in Rivendell to the forests of Ithilien -- both real areas,
        # on opposite sides of the map and of Mordor. Nothing in a name check
        # can see that; the transition graph can.
        if adjacency and len(p.get("areas") or []) > 1:
            refs = [by_name.get(a.lower()) for a in p["areas"]]
            refs = [r for r in refs if r]
            far = []
            for i in range(len(refs) - 1):
                distance = hops(adjacency, refs[i], refs[i + 1], MAX_HOPS)
                if distance is None:
                    far.append(f"{p['areas'][i]} -> {p['areas'][i + 1]}")
            if far:
                warnings.append(f"areas more than {MAX_HOPS} transitions apart "
                                f"(or unconnected): " + "; ".join(far[:2]))
        p["warnings"] = warnings
    return proposals


FETCH_VERBS = ("retrieve", "recover", "collect", "gather", "fetch", "bring back",
               "return the", "return it", "deliver", "harvest", "obtain")


def shape_report(proposals: list[dict]) -> list[str]:
    """Batch-level structural sameness -- the tics() of quest design.

    Per-proposal checks cannot see this: each quest is individually fine and the
    set is a monoculture. That is precisely how forty-three quest lines shipped
    before anyone noticed they were one quest with the nouns swapped.
    """
    if len(proposals) < 2:
        return []
    total = len(proposals)
    out = []

    fetchy = sum(1 for p in proposals
                 if any(v in " ".join(p.get("steps", [])).lower() for v in FETCH_VERBS))
    if fetchy / total >= 0.5:
        out.append(f"{fetchy}/{total} are still fetch-and-return despite the "
                   f"assigned shapes")

    openers = {}
    closers = {}
    for p in proposals:
        steps = p.get("steps") or []
        if not steps:
            continue
        first = " ".join(steps[0].lower().split()[:2])
        last = " ".join(steps[-1].lower().split()[:2])
        openers[first] = openers.get(first, 0) + 1
        closers[last] = closers.get(last, 0) + 1
    for label, counts in (("open", openers), ("end", closers)):
        phrase, count = max(counts.items(), key=lambda kv: kv[1], default=("", 0))
        if count > 1 and count / total >= 0.5:
            out.append(f"{count}/{total} {label} with {phrase!r}")

    lengths = {len(p.get("steps") or []) for p in proposals}
    if len(lengths) == 1 and total >= 3:
        out.append(f"every proposal has exactly {lengths.pop()} steps")
    return out


def to_notes(p: dict) -> str:
    steps = "".join(f"<li>{s}</li>" for s in p.get("steps", []))
    return (f"<p><b>Proposed quest line.</b> {p['premise']}</p>"
            f"<p><b>Steps:</b></p><ol>{steps}</ol>"
            f"<p><b>Areas:</b> {', '.join(p.get('areas', [])) or 'not specified'}<br>"
            f"<b>Reward:</b> {p.get('reward', 'not specified')}</p>"
            f"<p><i>Drafted by the local Gemma model via "
            f"<code>bin/llm/quest_ideas.py</code>. Unreviewed -- hidden until "
            f"someone decides it is worth building.</i></p>")


def file_ideas(proposals: list[dict]) -> int:
    """Append as hidden ideas, through the editor's own serializer and lock."""
    ed = load_editor()
    path = config.REPO / "roadmap.yaml"
    with ed.yaml_lock(timeout=60.0):
        text = path.read_text(encoding="utf-8")
        doc = yaml.load(text, Loader=ed._YamlLoader)
        ideas = doc["ideas"]
        existing = {i["id"] for i in ideas}
        added = 0
        for p in proposals:
            iid = p["id"]
            while iid in existing:          # never clobber an existing row
                iid += "-2"
            existing.add(iid)
            ideas.append({
                "id": iid,
                "title": p["title"],
                "group": GROUP,
                "status": STATUS,
                "type": "Enhancement",
                "player": PLAYER,
                "hidden": True,
                "notes": ed.sanitize_notes(to_notes(p)),
            })
            added += 1

        errors, warnings = ed.validate_document(ideas, doc.get("groups"),
                                                doc.get("players"))
        for w in warnings:
            print(f"  warning: {w}")
        if errors:
            for e in errors:
                print(f"  error: {e}", file=sys.stderr)
            raise SystemExit("roadmap.yaml would not validate; nothing written")

        head, prefixes, trailing = ed.split_head_and_prefixes(text)
        body = ed.serialize_ideas(ideas, prefixes, trailing)
        new = ed.replace_block(text, "ideas", body)
        yaml.load(new, Loader=ed._YamlLoader)   # prove the emitter's output parses
        path.write_text(new, encoding="utf-8")
    return added


def main(argv: list[str] | None = None) -> int:
    ap = argparse.ArgumentParser(description=__doc__,
                                 formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--count", type=int, default=5)
    ap.add_argument("--theme", default="", help="steer the proposals")
    ap.add_argument("--seed", type=int, default=0, help="0 = new sample each run")
    ap.add_argument("--apply", action="store_true",
                    help="file them into roadmap.yaml as hidden ideas")
    ap.add_argument("--include-flagged", action="store_true",
                    help="file proposals that failed a check too")
    args = ap.parse_args(argv)

    client = Client()
    ok, message = client.health()
    if not ok:
        print(f"gemma box unavailable: {message}", file=sys.stderr)
        return 3

    print(f"proposing {args.count} quest lines"
          + (f" on '{args.theme}'" if args.theme else "") + "...")
    try:
        proposals = propose(client, args.count, args.theme,
                            args.seed or random.randrange(1 << 30))
    except LLMUnavailable as exc:
        print(f"box went away: {exc}", file=sys.stderr)
        return 3

    if not proposals:
        print("the model proposed nothing")
        return 1

    for p in proposals:
        flag = "  !" if p["warnings"] else "  ."
        print(f"\n{flag} {p['id']}  (confidence {p.get('confidence')})")
        print(f"    {p['title']}")
        print(f"    {p['premise']}")
        for step in p.get("steps", []):
            print(f"      - {step}")
        print(f"    areas: {', '.join(p.get('areas', []))}")
        print(f"    reward: {p.get('reward', '')}")
        for w in p["warnings"]:
            print(f"    ! {w}")

    sameness = shape_report(proposals)
    if sameness:
        print("\n  structural sameness across the batch "
              "(the complaint that withdrew 43 quest lines):")
        for line in sameness:
            print(f"    - {line}")

    good = [p for p in proposals if args.include_flagged or not p["warnings"]]
    print(f"\n{len(good)} of {len(proposals)} passed the checks")
    if not args.apply:
        print("nothing written. Re-run with --apply to file them as hidden ideas.")
        return 0
    if not good:
        print("nothing to file")
        return 1

    added = file_ideas(good)
    print(f"\nfiled {added} hidden idea(s) in roadmap.yaml (group '{GROUP}', "
          f"status '{STATUS}')")
    print("They are hidden: off the public roadmap and the in-game sign until "
          "you unhide them.")
    print("Next: python3 bin/roadmap-lint.py")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
