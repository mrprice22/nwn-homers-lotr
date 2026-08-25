"""The Task contract.

A task is six pure-Python members plus one prompt. Everything that can be
decided without a model IS decided without a model -- which items to touch, what
context to give, whether the result is acceptable, where it gets written, and
how much human attention it deserves. The model supplies prose and nothing else.

That split is the whole point of the harness: the expensive thinking happens
once, here, when the task is written; every run afterwards is mechanical.
"""
from __future__ import annotations

import hashlib
from dataclasses import dataclass, field
from pathlib import Path
from typing import Any, Callable

# Importable both as a package module and via bin/ on sys.path.
if __package__ in (None, ""):
    import pathlib as _pathlib
    import sys as _sys
    _sys.path.insert(0, str(_pathlib.Path(__file__).resolve().parents[2]))

from llm import gff
from llm.tasks import validators as V


@dataclass
class Item:
    """One unit of work: a file, plus everything needed to prompt about it."""
    key: str                       # stable id, usually the resref
    path: Path                     # file to edit
    field: str                     # dotted path for gff.write_path
    context: str                   # the prompt payload, already resolved
    before: Any = None
    extra: dict = field(default_factory=dict)


@dataclass
class Result:
    item: Item
    text: str
    warnings: list[str] = field(default_factory=list)
    confidence: float | None = None
    dupe_of: str | None = None
    dupe_score: float = 0.0
    # Which model actually produced this. None means the task's own model; the
    # Sonnet fallback sets it so the ledger and the review panel can show that
    # an item did not come from the local model's baseline.
    source: str | None = None

    @property
    def priority(self) -> float:
        return V.priority(self.warnings, self.confidence, self.dupe_score)


@dataclass
class Task:
    name: str
    description: str
    risk: str                       # "auto" | "review" | "hold" -- see ledger
    system: str
    prompt_version: int
    selector: Callable[[], list[Item]]
    schema: dict = field(default_factory=lambda: TEXT_SCHEMA)
    model: str = "default"
    temperature: float = 0.7
    max_chars: int = 350
    min_chars: int = 60
    allow_digits: bool = False
    dupe_threshold: float = 0.35
    user_template: str = "{context}\n\nWrite the text."
    style_angles: tuple[str, ...] = ()
    # Rebuilds the prompt Item for one key, WITHOUT the selector's "is this
    # field still empty" filter. Required for re-rolling: by the time you want
    # a second opinion on an item, its field is filled and the selector -- quite
    # correctly -- no longer offers it.
    item_builder: Callable[[str], "Item | None"] | None = None
    # The GFF field this task writes. Re-roll resolves a task by FIELD rather
    # than by the ledger record's task name, because the newest record for a
    # field can come from a migration script (`desc_to_unidentified`) that is
    # not a generator and cannot regenerate anything.
    field: str = ""

    # -- prompting --------------------------------------------------------
    def angle(self, item: Item) -> str:
        """A rotating instruction hint, chosen deterministically from the key.

        Left to itself the model writes the same description over and over --
        two unrelated rings both came back as "a heavy band of tarnished silver
        ... sits upon the finger with a weight that". Detecting that afterwards
        is the near-duplicate check's job, but detection only tells you to throw
        work away. Forcing each item down a different angle prevents the
        collision instead, costs no tokens, and is stable across re-runs so the
        response cache still hits.
        """
        if not self.style_angles:
            return ""
        digest = hashlib.sha256(item.key.encode()).digest()
        return self.style_angles[digest[0] % len(self.style_angles)]

    def user_prompt(self, item: Item) -> str:
        return self.user_template.format(context=item.context, key=item.key,
                                         angle=self.angle(item))

    def parse(self, raw: dict | str) -> tuple[str, float | None]:
        if isinstance(raw, str):
            return raw, None
        return str(raw.get("text") or raw.get("desc") or ""), raw.get("confidence")

    # -- validation -------------------------------------------------------
    def validate(self, text: str, item: Item) -> tuple[str, list[str]]:
        """Returns (cleaned text, warnings). Never raises -- warnings drive review."""
        cleaned = V.clean(text)
        checks = [
            V.too_long(cleaned, self.max_chars),
            V.too_short(cleaned, self.min_chars),
            V.no_typographic(text),
            V.no_wrapping_quotes(text),
            V.no_markdown(cleaned),
            V.stutter(cleaned),
            V.invented_names(cleaned, item.context),
        ]
        if not self.allow_digits:
            checks.append(V.no_digits(cleaned))
        # Only meaningful where the item's real properties are known, which is
        # why they are carried on Item.extra rather than re-derived here.
        properties = item.extra.get("properties")
        if properties:
            checks.append(V.unfounded_claims(cleaned, properties))
        return cleaned, [c for c in checks if c]

    def mark_duplicates(self, results: list[Result],
                        seen: dict[str, str] | None = None) -> None:
        """Batch-level pass. Must run before anything is applied.

        `seen` carries the text of earlier chunks, so splitting a run into
        chunks does not blind the duplicate check across chunk boundaries --
        which would defeat the point of having it on a 944-item batch.
        """
        texts = dict(seen or {})
        texts.update({r.item.key: r.text for r in results if r.text})
        dupes = V.near_duplicates(texts, self.dupe_threshold)
        for result in results:
            hit = dupes.get(result.item.key)
            if hit:
                result.dupe_of, result.dupe_score = hit
                result.warnings.append(f"near-duplicate of {hit[0]} ({hit[1]})")

    # -- writing ----------------------------------------------------------
    def apply(self, result: Result) -> None:
        data = gff.load(result.item.path)
        gff.write_path(data, result.item.field, result.text)
        gff.dump(result.item.path, data)


TEXT_SCHEMA = {
    "type": "object",
    "properties": {
        "text": {"type": "string"},
        "confidence": {"type": "number"},
    },
    "required": ["text", "confidence"],
}

CONFIDENCE_NOTE = (
    "Also return `confidence`: 0.0 to 1.0, how sure you are that this needs no "
    "human edit. Be honest -- a low score costs nothing, a wrong claim costs a "
    "reviewer's time."
)
