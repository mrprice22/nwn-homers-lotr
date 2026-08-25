#!/usr/bin/env python3
"""Regenerate descriptions that were written under rules since corrected.

    python3 bin/llm/regenerate.py --list
    python3 bin/llm/regenerate.py --mode claims --limit 20 --dry-run
    python3 bin/llm/regenerate.py --mode all --apply

Two reasons text needs redoing, both found by auditing rather than by a failure:

  ranking  The power hint it was written from was computed off the wrong number
           -- dice ranked by their COUNT (2d12 as "2"), and Damage Reduction by
           the enhancement level that BYPASSES it rather than the damage it
           soaks. Corrected in llm/itemstats.py; anything generated before that
           was told the wrong thing about how strong the item is.

  claims   The text asserts a capability the item does not grant -- boots with
           only AC and Damage Reduction promising the wearer could move
           "without alerting the slightest prey". Detected by
           validators.unfounded_claims().

**Approved text is never regenerated.** Approval is the reviewer saying they want
that text; a correction elsewhere is not licence to overwrite it. Approved items
are excluded from every mode and reported separately so nothing goes silently
unfixed.

This exists rather than reusing run.py because the tasks' selectors deliberately
skip items whose field is already written -- which is every item here. Selection
is by explicit resref, and the prompt is rebuilt through Task.item_builder.
"""
from __future__ import annotations

import argparse
import glob
import re
import sys
import time

if __package__ in (None, ""):
    import pathlib as _pathlib
    _p = str(_pathlib.Path(__file__).resolve().parents[1])
    if _p not in sys.path:
        sys.path.insert(0, _p)

from llm import config, fallback, gff, itemstats, ledger
from llm.client import Client, LLMUnavailable
from llm.run import generate, write_chunk
from llm.tasks import registry
from llm.tasks.validators import unfounded_claims

FIELDS = {"unidentified": ("Description.value.0", "Description", "item_desc"),
          "identified": ("DescIdentified.value.0", "DescIdentified", "item_desc_id")}

DICE = re.compile(r"\b\d+d\d+\b")


def current_prompt_versions() -> dict[str, int]:
    return {t.field: t.prompt_version for t in registry().values() if t.field}


def latest_records() -> dict[tuple[str, str], dict]:
    """Newest ledger record per (file, field), by timestamp.

    By timestamp, not by read order: batches sort newest-first but records
    within a file keep append order, so file order gets this wrong whenever a
    field was written more than once in a batch.
    """
    latest: dict[tuple[str, str], dict] = {}
    for rec in ledger.read_all():
        if not rec.get("after"):
            continue
        key = (rec.get("file"), rec.get("field"))
        if key not in latest or (rec.get("ts") or "") > (latest[key].get("ts") or ""):
            latest[key] = rec
    return latest


def approved_set() -> set[tuple[str, str]]:
    return {(r["file"], r["field"]) for r in ledger.read_all()
            if r.get("review") == "approved"
            and r.get("task") in ("item_desc", "item_desc_id")}


def ranking_changed(resref: str) -> bool:
    """True when this item carries a property the old parser mis-ranked."""
    for _, name, rest in itemstats.split_properties(
            itemstats.wiki.item_properties(resref)):
        if name == "Damage Reduction" or DICE.search(rest):
            return True
    return False


def survey(modes: set[str]) -> tuple[list[tuple[str, str]], int]:
    """[(resref, slot)] needing work, plus how many were skipped as approved."""
    approved = approved_set()
    versions = current_prompt_versions()
    latest = latest_records()
    out: list[tuple[str, str]] = []
    skipped = up_to_date = 0
    for path in sorted(glob.glob(str(config.UNPACKED / "*.uti.json"))):
        resref = gff.resref_of(path)
        rel = f"unpacked/{resref}.uti.json"
        try:
            brief = itemstats.item_brief(resref)
        except Exception:  # noqa: BLE001
            continue
        properties = "; ".join(brief["properties"])
        if not properties:
            continue
        data = gff.load(path)
        by_ranking = "ranking" in modes and ranking_changed(resref)

        for slot, (field, key, _task) in FIELDS.items():
            text = gff.read_loc(data, key)
            if not text:
                continue
            wanted = by_ranking
            if "claims" in modes and unfounded_claims(text, properties):
                wanted = True
            if not wanted:
                continue
            if (rel, field) in approved:
                skipped += 1
                continue
            # "ranking" is a property of the ITEM, not of its text, so it stays
            # true forever once true. Without this check the queue reports every
            # affected item on every run -- 860 of 871 had already been redone --
            # and acting on that rewrites hours of good text for nothing.
            rec = latest.get((rel, field))
            if (rec and rec.get("prompt_version", 0) >= versions.get(field, 10 ** 6)
                    and not unfounded_claims(text, properties)):
                up_to_date += 1
                continue
            out.append((resref, slot))
    return out, skipped, up_to_date


def main(argv: list[str] | None = None) -> int:
    ap = argparse.ArgumentParser(description=__doc__,
                                 formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--mode", default="all", choices=("ranking", "claims", "all"))
    ap.add_argument("--slot", default="both",
                    choices=("both", "unidentified", "identified"))
    ap.add_argument("--limit", type=int, default=0)
    ap.add_argument("--chunk", type=int, default=50)
    ap.add_argument("--concurrency", type=int, default=config.CONCURRENCY)
    ap.add_argument("--apply", action="store_true")
    ap.add_argument("--list", action="store_true", help="report the queue and exit")
    ap.add_argument("--no-fallback", action="store_true")
    ap.add_argument("--max-fallback", type=int, default=fallback.DEFAULT_CAP)
    args = ap.parse_args(argv)

    modes = {"ranking", "claims"} if args.mode == "all" else {args.mode}
    work, skipped, up_to_date = survey(modes)
    if args.slot != "both":
        work = [w for w in work if w[1] == args.slot]

    by_slot: dict[str, int] = {}
    for _, slot in work:
        by_slot[slot] = by_slot.get(slot, 0) + 1
    print(f"mode={args.mode} slot={args.slot}")
    print(f"  queue: {len(work)}  ({', '.join(f'{v} {k}' for k, v in sorted(by_slot.items())) or 'nothing'})")
    print(f"  skipped as already approved: {skipped}")
    print(f"  already current (regenerated under these rules): {up_to_date}")
    if args.list or not work:
        return 0

    if args.limit:
        work = work[: args.limit]

    tasks = registry()
    client = Client()
    ok, message = client.health()
    if not ok:
        print(f"gemma box unavailable: {message}", file=sys.stderr)
        return 3

    budget = None
    if not args.no_fallback and args.max_fallback > 0 and fallback.available():
        budget = fallback.Budget(args.max_fallback)
        print(f"  fallback {fallback.SOURCE} (cap {args.max_fallback})")

    # One batch per slot: the two slots are different tasks with different
    # prompts, and mixing them in a ledger batch would make the panel's grouping
    # meaningless.
    total_written = 0
    started = time.monotonic()
    for slot in ("unidentified", "identified"):
        refs = [r for r, s in work if s == slot]
        if not refs:
            continue
        task = tasks[FIELDS[slot][2]]
        items = [i for i in (task.item_builder(r) for r in refs) if i]
        print(f"\n{task.name}: regenerating {len(items)}")
        if not args.apply:
            for item in items[:3]:
                print(f"  would rewrite {item.field} in {item.path.name}")
            print(f"  ... and {max(0, len(items) - 3)} more (dry run)")
            continue

        batch = ledger.batch_id(f"regen-{task.name}")
        book = ledger.Ledger(batch)
        seen: dict[str, str] = {}
        for offset in range(0, len(items), args.chunk):
            chunk = items[offset:offset + args.chunk]
            # `before` must be what is on disk right now, so a revert restores
            # the text being replaced rather than an empty field.
            for item in chunk:
                item.before = gff.read_path(gff.load(item.path), item.field)
            try:
                got = generate(task, client, chunk, args.concurrency, seen,
                               progress=True, budget=budget)
            except LLMUnavailable as exc:
                print(f"\nbox went away: {exc}; {total_written} written so far",
                      file=sys.stderr)
                return 3
            seen.update({r.item.key: r.text for r in got if r.text})
            written = write_chunk(task, client, book, batch, got, include_flagged=False)
            total_written += written
            print(f"  applied {total_written} so far")
        print(f"  ledger: {book.path.relative_to(config.REPO)}")

    if args.apply:
        print(f"\nregenerated {total_written} in {(time.monotonic()-started)/60:.0f} min")
        print(f"{client.usage.summary(time.monotonic()-started)}")
        if budget and budget.spent:
            print(f"  {budget.spent} recovered by {fallback.SOURCE}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
