#!/usr/bin/env python3
"""Design class questlines with the local Gemma model, one quest at a time.

    python3 bin/llm/questlines.py --list            # what is done, what is left
    python3 bin/llm/questlines.py --once            # design ONE quest, then stop
    python3 bin/llm/questlines.py --only fighter    # just that class
    python3 bin/llm/questlines.py                   # work every backlog to the end

A Python port of `gemma-questlines/run-loop.ps1`, which stays in place unchanged.
The design is the PowerShell script's and is preserved exactly -- the same
backlog files, the same checkbox ticking, the same output and synopsis files, in
the same formats. Only the plumbing changed:

  * **The box is reached over the network** (`llm/config.OLLAMA_URL`), not
    `localhost`. The .ps1 assumed it was running ON the Windows machine.
  * **The model comes from the shared registry.** The .ps1 defaulted to
    `gemma4:12b-it-qat`, which is not installed there -- only the three
    `hf.co/unsloth/gemma-4-*` builds are, so that default could only ever fail.
  * **It goes through `llm/client.py`**, so it gets the disk cache, retries, the
    health probe and `status.py` visibility like every other task here.
  * **Classes run in parallel.** Quests *within* a line must stay sequential --
    each one is prompted with a synopsis of the ones before it -- but the 21
    lines are independent, so they run concurrently. That is the difference
    between about six hours and about two for the 192 outstanding quests.

Output is markdown design documents under `gemma-questlines/output/`, not module
content, so there is no ledger entry and no build gate: these are proposals for a
human to read, and `git diff` is the review path. Nothing here writes to
`unpacked/`, and nothing here is a quest the module can run.
"""
from __future__ import annotations

import argparse
import re
import sys
import threading
import time
from dataclasses import dataclass, field
from pathlib import Path

if __package__ in (None, ""):
    import pathlib as _pathlib
    _p = str(_pathlib.Path(__file__).resolve().parents[1])
    if _p not in sys.path:
        sys.path.insert(0, _p)

from llm import config
from llm.client import Client, LLMError, LLMUnavailable

ROOT = Path(__file__).resolve().parent / "gemma-questlines"
BACKLOG_DIR = ROOT / "backlog"
OUTPUT_DIR = ROOT / "output"
SYNOPSIS_DIR = OUTPUT_DIR / ".synopsis"
BRIEF = ROOT / "prompts" / "design-brief.md"

SLOT = re.compile(r"^- \[( |x)\] Q(\d+) L(\d+)")
BOM = "﻿"

# The .ps1 set this deliberately and it matters. The prompt grows as a line
# progresses -- every finished quest adds a synopsis line to "STORY SO FAR" --
# while the box loads this model at 4096. On overflow Ollama drops the front of
# the request, which is the design brief: the output format, the reward tiers and
# the do-not-repeat-yourself rule would all vanish, worst on the late capstone
# quests, and the result would still look like a perfectly good quest.
NUM_CTX = 8192

# Sections the design brief's OUTPUT FORMAT demands. A response missing one is
# not a usable design document, whatever else it says.
REQUIRED = ("**Hook:**", "**Setting:**", "**Objectives:**", "**Rewards:**",
            "SYNOPSIS:")


# -- file io that survives a PowerShell round-trip --------------------------
def read_text(path: Path) -> str:
    """Read, dropping a BOM. PowerShell 5.1 writes UTF-8 with one."""
    return path.read_text(encoding="utf-8-sig")


def write_text(path: Path, text: str, *, bom: bool, crlf: bool) -> None:
    """Write back in the encoding the file already had.

    Normalising these would be a one-line change and a bad one: Windows
    PowerShell 5.1's Get-Content misreads BOM-less UTF-8, so stripping the BOM
    would quietly corrupt any non-ASCII in the backlogs the moment the .ps1 ran
    against them again.
    """
    if crlf:
        text = text.replace("\r\n", "\n").replace("\n", "\r\n")
    path.write_text((BOM if bom else "") + text, encoding="utf-8", newline="")


def file_style(path: Path) -> tuple[bool, bool]:
    """(has_bom, has_crlf) for an existing file; PowerShell's style if new."""
    if not path.exists():
        return True, True
    raw = path.read_bytes()
    return raw.startswith(b"\xef\xbb\xbf"), b"\r\n" in raw


def append_text(path: Path, text: str) -> None:
    bom, crlf = file_style(path)
    existing = read_text(path) if path.exists() else ""
    write_text(path, existing + text, bom=bom, crlf=crlf)


# -- backlog model ----------------------------------------------------------
@dataclass
class Slot:
    done: bool
    index: int
    level: int
    raw: str


@dataclass
class Line:
    name: str            # backlog stem, e.g. "fighter"
    title: str           # "Fighter"
    premise: str
    tone: str
    kind: str            # "base" | "prestige"
    slots: list[Slot]
    path: Path
    lock: threading.Lock = field(default_factory=threading.Lock, repr=False)

    @property
    def total(self) -> int:
        return len(self.slots)

    @property
    def remaining(self) -> int:
        return sum(1 for s in self.slots if not s.done)

    def next_slot(self) -> Slot | None:
        return next((s for s in self.slots if not s.done), None)


def field_value(lines: list[str], key: str) -> str:
    for line in lines:
        if line.startswith(key + ":"):
            return line[len(key) + 1:].strip()
    return ""


def load_line(path: Path) -> Line | None:
    lines = read_text(path).splitlines()
    slots = []
    for line in lines:
        m = SLOT.match(line)
        if m:
            slots.append(Slot(done=m.group(1) == "x", index=int(m.group(2)),
                              level=int(m.group(3)), raw=line))
    if not slots:
        return None
    title = next((l[2:].strip() for l in lines if l.startswith("# ")), path.stem)
    title = title.replace(" Questline Backlog", "").strip()
    return Line(name=path.stem, title=title,
                premise=field_value(lines, "Premise"),
                tone=field_value(lines, "Tone"),
                kind=field_value(lines, "Type") or "base",
                slots=slots, path=path)


def load_all(only: str = "") -> list[Line]:
    if not BACKLOG_DIR.is_dir():
        raise SystemExit(f"no backlog directory at {BACKLOG_DIR}")
    out = []
    for path in sorted(BACKLOG_DIR.glob("*.md")):
        if only and path.stem != only:
            continue
        line = load_line(path)
        if line:
            out.append(line)
    return out


def tier(index: int, total: int) -> str:
    """Reward tier for quest `index` of `total`. Mirrors Get-Tier in the .ps1."""
    if index == total:
        return "Legendary capstone"
    fraction = index / total
    if fraction <= 0.25:
        return "Apprentice"
    if fraction <= 0.5:
        return "Journeyman"
    if fraction <= 0.75:
        return "Veteran"
    return "Master"


# -- one quest --------------------------------------------------------------
def story_so_far(line: Line) -> str:
    path = SYNOPSIS_DIR / f"{line.name}.txt"
    if path.exists():
        text = read_text(path).strip()
        if text:
            return text
    return "None yet - this is the opening quest of the line."


def build_prompt(line: Line, slot: Slot) -> str:
    return (
        f"CLASS: {line.title}\n"
        f"CLASS TYPE: {line.kind}\n"
        f"QUESTLINE PREMISE: {line.premise}\n"
        f"TONE: {line.tone}\n\n"
        "STORY SO FAR (previously designed quests; do NOT repeat their structure, "
        "hooks, locations, foes, or rewards - escalate beyond them):\n"
        f"{story_so_far(line)}\n\n"
        f"YOUR TASK: Design quest #{slot.index} of {line.total} for the "
        f"{line.title}, set at character level {slot.level}.\n"
        f"Reward tier: {tier(slot.index, line.total)}.\n"
        "Output ONLY the quest in the required OUTPUT FORMAT."
    )


def check(text: str) -> list[str]:
    missing = [s for s in REQUIRED if s not in text]
    problems = []
    if missing:
        problems.append("missing sections: " + ", ".join(missing))
    if not text.lstrip().startswith("## Quest"):
        problems.append("does not start with a '## Quest N:' heading")
    return problems


def record(line: Line, slot: Slot, text: str) -> None:
    """Append the quest, its synopsis, and tick the box. Same formats as the .ps1."""
    with line.lock:
        append_text(OUTPUT_DIR / f"{line.name}.md", f"\n{text}\n\n---\n")

        synopsis = next((l for l in text.splitlines() if l.startswith("SYNOPSIS:")), "")
        synopsis = synopsis[len("SYNOPSIS:"):].strip() if synopsis else \
            f"(quest {slot.index} at level {slot.level})"
        append_text(SYNOPSIS_DIR / f"{line.name}.txt",
                    f"Q{slot.index}: {synopsis}\n")

        bom, crlf = file_style(line.path)
        body = read_text(line.path)
        # Replace this slot's line only -- matching on the exact raw text, as the
        # .ps1 does, so a duplicated level cannot tick the wrong box.
        out = []
        ticked = False
        for existing in body.splitlines():
            if not ticked and existing.rstrip("\r") == slot.raw.rstrip("\r"):
                existing = re.sub(r"^- \[ \]", "- [x]", existing)
                ticked = True
            out.append(existing)
        write_text(line.path, "\n".join(out) + "\n", bom=bom, crlf=crlf)
        slot.done = True


def design_one(client: Client, brief: str, line: Line, slot: Slot,
               dry_run: bool) -> tuple[bool, str]:
    if dry_run:
        return True, (f"[dry run] {line.name} Q{slot.index}/{line.total} "
                      f"L{slot.level} {tier(slot.index, line.total)}")
    try:
        text = client.chat(brief, build_prompt(line, slot), schema=None,
                           prompt_version=1, temperature=0.8, num_ctx=NUM_CTX)
    except LLMUnavailable:
        raise
    except LLMError as exc:
        return False, f"{line.name} Q{slot.index}: {exc}"

    text = re.sub(r"\x1b\[[0-9;]*[A-Za-z]", "", str(text)).strip()
    if not text:
        return False, f"{line.name} Q{slot.index}: empty response, box not ticked"
    problems = check(text)
    if problems:
        return False, f"{line.name} Q{slot.index}: " + "; ".join(problems)

    record(line, slot, text)
    heading = text.splitlines()[0].strip()
    return True, f"{line.name} Q{slot.index}/{line.total} L{slot.level}: {heading}"


# -- driving ----------------------------------------------------------------
def show_list(lines: list[Line]) -> None:
    done = total = 0
    print(f"{'line':<22} {'kind':<9} {'progress':>10}")
    print("-" * 45)
    for line in lines:
        d = line.total - line.remaining
        done += d
        total += line.total
        bar = "complete" if line.remaining == 0 else f"{d}/{line.total}"
        print(f"{line.name:<22} {line.kind:<9} {bar:>10}")
    print("-" * 45)
    print(f"{'TOTAL':<22} {'':<9} {f'{done}/{total}':>10}"
          f"   ({total - done} quests outstanding)")


def main(argv: list[str] | None = None) -> int:
    ap = argparse.ArgumentParser(description=__doc__,
                                 formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--only", default="", help="one backlog, by name (e.g. fighter)")
    ap.add_argument("--once", action="store_true", help="design one quest, then stop")
    ap.add_argument("--limit", type=int, default=0, help="stop after N quests")
    ap.add_argument("--list", action="store_true", help="show progress and exit")
    ap.add_argument("--model", default=None)
    ap.add_argument("--concurrency", type=int, default=config.CONCURRENCY,
                    help="how many CLASSES to design in parallel (quests within "
                         "a class are always sequential -- they build on each other)")
    ap.add_argument("--dry-run", action="store_true",
                    help="report what would be designed; call nothing, write nothing")
    args = ap.parse_args(argv)

    if not BRIEF.exists():
        raise SystemExit(f"design brief missing: {BRIEF}")
    lines = load_all(args.only)
    if not lines:
        raise SystemExit(f"no backlogs found in {BACKLOG_DIR}"
                         + (f" matching {args.only!r}" if args.only else ""))

    if args.list:
        show_list(lines)
        return 0

    OUTPUT_DIR.mkdir(parents=True, exist_ok=True)
    SYNOPSIS_DIR.mkdir(parents=True, exist_ok=True)
    brief = read_text(BRIEF)

    client = Client(args.model)
    if not args.dry_run:
        ok, message = client.health()
        if not ok:
            print(f"gemma box unavailable: {message}", file=sys.stderr)
            return 3
        print(f"questlines: {message}\n  model {client.model}")

    outstanding = sum(l.remaining for l in lines)
    budget = 1 if args.once else (args.limit or outstanding)
    print(f"  {outstanding} quests outstanding across {len(lines)} line(s); "
          f"designing {min(budget, outstanding)}"
          + (f" at concurrency {args.concurrency}" if budget > 1 else ""))

    counter = threading.Lock()
    state = {"done": 0, "failed": 0, "budget": budget}
    started = time.monotonic()

    def take() -> bool:
        with counter:
            if state["budget"] <= 0:
                return False
            state["budget"] -= 1
            return True

    def work(line: Line) -> None:
        """One class, start to finish -- quests here must stay in order."""
        while line.remaining and take():
            slot = line.next_slot()
            if slot is None:
                return
            ok, message = design_one(client, brief, line, slot, args.dry_run)
            with counter:
                if ok:
                    state["done"] += 1
                    print(f"  ok  {message}")
                else:
                    state["failed"] += 1
                    print(f"  !!  {message}")
                    # Do not keep hammering a line that is failing; its synopsis
                    # chain is what the next quest depends on.
                    state["budget"] += 1
                    return

    try:
        if args.concurrency > 1 and len(lines) > 1:
            from concurrent.futures import ThreadPoolExecutor
            with ThreadPoolExecutor(max_workers=args.concurrency) as pool:
                list(pool.map(work, lines))
        else:
            for line in lines:
                work(line)
    except LLMUnavailable as exc:
        print(f"\nbox went away: {exc}\n"
              f"{state['done']} quests were written and their boxes ticked; "
              f"re-run to continue.", file=sys.stderr)
        return 3
    except KeyboardInterrupt:
        print(f"\ninterrupted after {state['done']} quests -- all of them written "
              f"and ticked. Re-run to continue.")
        return 130

    elapsed = time.monotonic() - started
    print(f"\n{state['done']} designed, {state['failed']} failed, "
          f"{sum(l.remaining for l in lines)} still outstanding")
    if not args.dry_run:
        print(client.usage.summary(elapsed))
        print(f"output: {OUTPUT_DIR.relative_to(config.REPO)}/  "
              f"-- review with `git diff`")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
