#!/usr/bin/env python3
"""Semantic duplicate check for roadmap ideas.

    python3 bin/llm/roadmap_dupe.py --id add-custom-helmet-skins
    python3 bin/llm/roadmap_dupe.py --title "let players dye armour" --group forge
    python3 bin/llm/roadmap_dupe.py --all

Read-only: it prints candidates and never touches roadmap.yaml. Setting
`dupe_of` stays a human decision, because merging two players' ideas also merges
who gets the merit credit for them.

Why this exists. `bin/gen-roadmap.py` warns on duplicates by word overlap of
normalised titles at a 0.7 threshold, within a group. That catches "Add bank to
Bree" against "Add a bank in Bree" and misses "Add a banker NPC to Bree" -- the
duplicates that actually get filed, because two players describing the same wish
rarely pick the same nouns. It also cannot see across groups at all.

Two strategies, in order of preference:

  embeddings  cosine similarity over title + notes. One pass over the backlog,
              no generation. Needs an embedding model on the box -- there is
              none installed as of 2026-08-23, and `--embeddings` is a llama.cpp
              flag that does nothing for Ollama. Fix: `ollama pull embeddinggemma`.

  generative  ask the 12B model to compare one candidate against the titles in
              its group. One call, ~30 titles of context. Slower per query but
              needs nothing installed, and it is the sensible default for the
              real use case: checking ONE newly filed idea, not re-scanning 356.

The word-overlap check in gen-roadmap.py stays as it is. This supplements it.
"""
from __future__ import annotations

import argparse
import json
import math
import sys

if __package__ in (None, ""):
    import pathlib as _pathlib
    _p = str(_pathlib.Path(__file__).resolve().parents[1])
    if _p not in sys.path:
        sys.path.insert(0, _p)

import yaml

from llm import config
from llm.client import Client, LLMUnavailable

SCHEMA = {
    "type": "object",
    "properties": {
        "duplicates": {
            "type": "array",
            "items": {
                "type": "object",
                "properties": {
                    "id": {"type": "string"},
                    "confidence": {"type": "number"},
                    "why": {"type": "string"},
                },
                "required": ["id", "confidence", "why"],
            },
        },
    },
    "required": ["duplicates"],
}

SYSTEM = """You spot duplicate feature requests in a game development backlog.

Two entries are duplicates when doing one would satisfy the person who asked for
the other. That is the only test. They are NOT duplicates merely because they
touch the same system, the same area or the same NPC -- a backlog for one game
is full of unrelated work in the same place.

Return only genuine duplicates, with a confidence from 0.0 to 1.0 and a short
reason. Returning an empty list is the correct and expected answer most of the
time. Do not pad the list."""


def load() -> list[dict]:
    data = yaml.safe_load((config.REPO / "roadmap.yaml").read_text())
    return [i for i in data["ideas"] if not i.get("dupe_of")]


def _text(idea: dict) -> str:
    parts = [idea.get("title") or ""]
    notes = (idea.get("notes") or "").strip()
    if notes:
        parts.append(notes[:300])
    return " -- ".join(parts)


def _cosine(a: list[float], b: list[float]) -> float:
    dot = sum(x * y for x, y in zip(a, b))
    na = math.sqrt(sum(x * x for x in a))
    nb = math.sqrt(sum(x * x for x in b))
    return dot / (na * nb) if na and nb else 0.0


def by_embedding(client: Client, ideas: list[dict], target: dict | None,
                 threshold: float) -> list[tuple[str, str, float]] | None:
    vectors = client.embed([_text(i) for i in ideas])
    if not vectors:
        return None
    hits = []
    if target is not None:
        vector = client.embed([_text(target)])
        if not vector:
            return None
        for idea, other in zip(ideas, vectors):
            if idea["id"] == target.get("id"):
                continue
            score = _cosine(vector[0], other)
            if score >= threshold:
                hits.append((target["id"], idea["id"], round(score, 3)))
    else:
        for a in range(len(ideas)):
            for b in range(a + 1, len(ideas)):
                score = _cosine(vectors[a], vectors[b])
                if score >= threshold:
                    hits.append((ideas[a]["id"], ideas[b]["id"], round(score, 3)))
    return sorted(hits, key=lambda h: -h[2])


def by_generation(client: Client, ideas: list[dict], target: dict,
                  cross_group: bool) -> list[tuple[str, str, float]]:
    pool = [i for i in ideas
            if i["id"] != target.get("id")
            and (cross_group or i.get("group") == target.get("group"))]
    if not pool:
        return []
    # Cap the context: a group can be large, and a wall of titles degrades the
    # judgement rather than improving recall.
    listing = "\n".join(f"- {i['id']}: {i.get('title', '')}" for i in pool[:80])
    user = (f"Candidate entry:\n- {target.get('id', '(new)')}: {_text(target)}\n\n"
            f"Existing entries:\n{listing}\n\n"
            f"Which existing entries, if any, are duplicates of the candidate?")
    result = client.chat(SYSTEM, user, SCHEMA, prompt_version=1, temperature=0.1)
    out = []
    known = {i["id"] for i in pool}
    for hit in (result or {}).get("duplicates", []):
        # The model does occasionally invent an id; drop those silently rather
        # than reporting a duplicate of something that does not exist.
        if hit.get("id") in known:
            out.append((target.get("id", "(new)"), hit["id"], float(hit.get("confidence", 0))))
    return sorted(out, key=lambda h: -h[2])


def main(argv: list[str] | None = None) -> int:
    ap = argparse.ArgumentParser(description=__doc__,
                                 formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--id", help="check an existing idea by id")
    ap.add_argument("--title", help="check a title that is not filed yet")
    ap.add_argument("--group", default="", help="group for --title")
    ap.add_argument("--all", action="store_true",
                    help="scan the whole backlog (embeddings only)")
    ap.add_argument("--cross-group", action="store_true",
                    help="compare against every group, not just the candidate's")
    ap.add_argument("--threshold", type=float, default=0.86,
                    help="cosine similarity cutoff for the embedding strategy")
    args = ap.parse_args(argv)

    if not (args.id or args.title or args.all):
        ap.error("give --id, --title or --all")

    ideas = load()
    target = None
    if args.id:
        target = next((i for i in ideas if i["id"] == args.id), None)
        if not target:
            print(f"no idea with id {args.id!r}", file=sys.stderr)
            return 2
    elif args.title:
        target = {"id": "(new)", "title": args.title, "group": args.group}

    client = Client()
    ok, message = client.health()
    if not ok:
        print(f"gemma box unavailable: {message}", file=sys.stderr)
        return 3

    try:
        hits = by_embedding(client, ideas, target, args.threshold)
        strategy = "embeddings"
        if hits is None:
            if args.all:
                print("--all needs an embedding model; none is installed.\n"
                      "  ollama pull embeddinggemma   (on the Gemma box)\n"
                      "Falling back is not possible for a whole-backlog scan: it "
                      "would be one generation per idea.", file=sys.stderr)
                return 4
            hits = by_generation(client, ideas, target, args.cross_group)
            strategy = "generation (no embedding model installed)"
    except LLMUnavailable as exc:
        print(f"box went away: {exc}", file=sys.stderr)
        return 3

    titles = {i["id"]: i.get("title", "") for i in ideas}
    print(f"strategy: {strategy}")
    if not hits:
        print("no likely duplicates")
        return 0
    for left, right, score in hits:
        print(f"\n  {score:.2f}  {left}\n        ~ {right}: {titles.get(right, '')}")
    print(f"\n{len(hits)} candidate pair(s). Setting `dupe_of` is your call -- "
          f"merging two ideas also merges who gets merit credit for them.")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
