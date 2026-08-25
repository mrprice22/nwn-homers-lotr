"""dlg_typos -- proofread NPC dialogue.

This repo already has a two-phase typo pipeline: `bin/fix-dlg-typos.py` applies
conservative regex fixes, and `bin/apply-dlg-corrections.py` applies a hardcoded
list of "LLM-reviewed" corrections that someone produced out of band. This task
is that out-of-band step, automated.

**Risk tier `review`, unlike every other task here.** It is the only one that
edits text a human wrote. That difference is the whole reason the review panel
exists, and the reason this task is deliberately timid:

  * It proposes corrections to individual lines, never rewrites them. Prompted to
    "improve" dialogue a model will happily flatten a character's voice into
    house style, and the module has NPCs who speak in deliberate dialect --
    exactly what `fix-dlg-typos.py`'s docstring warns regexes cannot distinguish.
  * A proposal identical to the original is dropped, so a file with no typos
    produces no records.
  * Third-party and DM-tool conversations are excluded: `dmfi_universal` alone is
    1,228 nodes of somebody else's toolset, and `sd_appear_conv` is a generated
    appearance menu.

One call per text node keeps the field path exact -- there is no fuzzy matching
back onto a rewritten file, and a revert is the same one-field write as anywhere
else.
"""
from __future__ import annotations

import re

if __package__ in (None, ""):
    import pathlib as _pathlib
    import sys as _sys
    _sys.path.insert(0, str(_pathlib.Path(__file__).resolve().parents[2]))

from llm import config, gff
from llm.tasks.base import Item, Task

SKIP_PREFIX = ("dmfi_", "sd_appear", "nw_", "x0_", "x2_", "ds_")
# Long enough to contain a typo worth finding and short enough to be one call.
MIN_LEN, MAX_LEN = 25, 900
# Token markers the engine substitutes at runtime. If the model "corrects" one
# the line silently breaks, so lines containing them are left alone.
TOKENS = re.compile(r"<[A-Za-z]+>|\$\{|%[A-Za-z]|\bCUSTOM\d+\b")

SCHEMA = {
    "type": "object",
    "properties": {
        "text": {"type": "string"},
        "changed": {"type": "boolean"},
        "reason": {"type": "string"},
        "confidence": {"type": "number"},
    },
    "required": ["text", "changed", "reason", "confidence"],
}

SYSTEM = """You proofread NPC dialogue for a Lord of the Rings themed Neverwinter Nights module.

Fix ONLY these, and nothing else:
  * misspellings
  * missing or doubled punctuation, and missing capitals at the start of a sentence
  * obvious grammatical slips ("your" for "you're", "there" for "their")
  * doubled words ("the the")

Do NOT:
  * rewrite, shorten, expand or "improve" the line
  * change the voice, register or dialect -- some characters speak in deliberate
    broken or archaic English and that is not an error
  * change wording you merely dislike
  * touch anything in angle brackets, percent signs or braces: those are engine
    tokens and altering one breaks the line
  * change American to British spelling or the reverse
  * add, remove or move line breaks -- a line laid out across several lines is
    laid out that way deliberately. Keep every newline exactly where it is.

Return the line with only those fixes applied. Set `changed` to false and return
the line untouched if there is nothing genuinely wrong with it -- that is the
expected answer most of the time. `reason` is a few words naming what you fixed,
or "no change". `confidence` is 0.0 to 1.0."""

TEMPLATE = """Speaker context: {context}

Proofread this line."""


def selector() -> list[Item]:
    items: list[Item] = []
    for path in sorted(config.UNPACKED.glob("*.dlg.json")):
        resref = gff.resref_of(path)
        if resref.startswith(SKIP_PREFIX):
            continue
        data = gff.load(path)
        for list_name in ("EntryList", "ReplyList"):
            nodes = (data.get(list_name) or {}).get("value") or []
            for index, node in enumerate(nodes):
                text = ((node.get("Text") or {}).get("value") or {}).get("0") or ""
                text = text.strip()
                if not (MIN_LEN <= len(text) <= MAX_LEN):
                    continue
                if TOKENS.search(text):
                    continue
                speaker = "an NPC" if list_name == "EntryList" else "the player"
                items.append(Item(
                    key=f"{resref}:{list_name}:{index}",
                    path=path,
                    field=f"{list_name}.value.{index}.Text.value.0",
                    context=f"conversation {resref}, spoken by {speaker}\n\n{text}",
                    before=text,
                    extra={"original": text},
                ))
    return items


class ProofreadTask(Task):
    def parse(self, raw):
        if isinstance(raw, str):
            return raw, None
        return str(raw.get("text") or ""), raw.get("confidence")

    def validate(self, text: str, item: Item) -> tuple[str, list[str]]:
        """A proofreading pass is judged against the original, not in isolation.

        The base checks are about writing new prose and mostly do not apply --
        dialogue legitimately contains digits, names and quotation marks. What
        matters is that the model did not quietly rewrite the line.
        """
        from llm.tasks import validators as V

        original = item.extra["original"]
        # keep_newlines: dialogue lines use line breaks for layout, and the
        # default clean() flattens them along with everything else.
        cleaned = V.clean(text, keep_newlines=True) if text else ""
        if not cleaned or cleaned == original:
            return "", []           # no change proposed; run.py drops empties

        warnings = []
        ratio = abs(len(cleaned) - len(original)) / max(len(original), 1)
        if ratio > 0.25:
            warnings.append(f"length changed {ratio:.0%} -- likely a rewrite, not a fix")
        original_words = original.lower().split()
        new_words = cleaned.lower().split()
        if abs(len(new_words) - len(original_words)) > 3:
            warnings.append("word count moved by more than three")
        if TOKENS.search(cleaned) != TOKENS.search(original):
            warnings.append("engine token altered")
        if cleaned.count("\n") != original.count("\n"):
            warnings.append(f"line breaks changed "
                            f"({original.count(chr(10))} -> {cleaned.count(chr(10))})")
        return cleaned, warnings


TASK = ProofreadTask(
    name="dlg_typos",
    description="Proofread NPC dialogue (typos and punctuation only)",
    risk="review",
    system=SYSTEM,
    user_template=TEMPLATE,
    prompt_version=2,
    selector=selector,
    schema=SCHEMA,
    temperature=0.2,
    max_chars=MAX_LEN,
    min_chars=1,
    allow_digits=True,
)
