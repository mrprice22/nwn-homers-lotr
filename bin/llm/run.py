#!/usr/bin/env python3
"""Run a task recipe against the local Gemma box.

    python3 bin/llm/run.py --list
    python3 bin/llm/run.py item_desc --limit 20 --dry-run
    python3 bin/llm/run.py item_desc --apply

Dry-run is the default. Nothing is written to unpacked/ and no ledger batch is
opened unless --apply is given.
"""
from __future__ import annotations

import argparse
import random
import sys
import time

if __package__ in (None, ""):
    import pathlib as _pathlib
    _sys_path = str(_pathlib.Path(__file__).resolve().parents[1])
    if _sys_path not in sys.path:
        sys.path.insert(0, _sys_path)

from llm import config, fallback, ledger
from llm.client import Client, LLMUnavailable
from llm.tasks import registry
from llm.tasks.base import Item, Result, Task


def generate(task: Task, client: Client, items: list[Item], concurrency: int,
             seen: dict[str, str] | None = None, progress: bool = False,
             budget: "fallback.Budget | None" = None,
             retry_rejects: bool = True) -> list[Result]:
    def one(item: Item) -> Result:
        raw = client.chat(
            task.system,
            task.user_prompt(item),
            task.schema,
            prompt_version=task.prompt_version,
            temperature=task.temperature,
        )
        text, confidence = task.parse(raw)
        cleaned, warnings = task.validate(text, item)

        # One more roll when validation rejects it. Without this a rejected
        # generation is cached, so re-running the batch serves the identical bad
        # text back and the queue can never drain -- measured at 4 rejects in 8
        # on the first corrected-prompt run, half of which passed on a re-roll.
        if warnings and retry_rejects:
            second = client.chat(
                task.system, task.user_prompt(item), task.schema,
                prompt_version=task.prompt_version,
                temperature=min(1.0, task.temperature + 0.05),
                nonce=random.randrange(1 << 30),
            )
            text2, conf2 = task.parse(second)
            cleaned2, warnings2 = task.validate(text2, item)
            if cleaned2 and not warnings2:
                cleaned, warnings, confidence = cleaned2, warnings2, conf2

        result = Result(item=item, text=cleaned, warnings=warnings, confidence=confidence)
        if not cleaned:
            # A structurally fine but empty answer is still a failure to produce
            # anything, so it earns the fallback like a raised error does.
            recovered = _fallback(item, "empty response")
            if recovered:
                return recovered
        return result

    def _fallback(item: Item, reason: str) -> Result | None:
        """Retry one item on Sonnet. Never raises; None means it stays failed."""
        if budget is None:
            return None
        raw, error = fallback.try_chat(task.system, task.user_prompt(item), budget,
                                       structured=task.schema is not None,
                                       schema=task.schema)
        if raw is None:
            return None
        text, confidence = task.parse(raw)
        cleaned, warnings = task.validate(text, item)
        if not cleaned:
            return None
        return Result(item=item, text=cleaned, warnings=warnings,
                      confidence=confidence, source=fallback.SOURCE)

    def failed(item: Item, exc: Exception) -> Result:
        recovered = _fallback(item, str(exc))
        if recovered:
            return recovered
        return Result(item=item, text="", warnings=[f"error: {exc}"], confidence=0.0)

    def tick(done: int, total: int) -> None:
        if done % 10 == 0 or done == total:
            print(f"    {done}/{total}", end="\r", flush=True)

    results = client.map(items, one, concurrency=concurrency, on_error=failed,
                         on_progress=tick if progress else None)
    results = [r for r in results if r is not None]
    if progress:
        print()
    task.mark_duplicates(results, seen)
    return results


def write_chunk(task: Task, client: Client, book: "ledger.Ledger", batch: str,
                results: list[Result], include_flagged: bool) -> int:
    """Apply one chunk and record it. Returns how many were written."""
    writable = [r for r in results if r.text and (include_flagged or not r.warnings)]
    records = []
    for result in writable:
        task.apply(result)
        records.append(ledger.Change(
            file=str(result.item.path.relative_to(config.REPO)),
            field=result.item.field,
            before=result.item.before,
            after=result.text,
            task=task.name,
            risk=task.risk,
            batch=batch,
            source=result.source or client.short_name,
            review="pending",
            priority=result.priority,
            warnings=result.warnings,
            confidence=result.confidence,
            prompt_version=task.prompt_version,
        ))
    book.extend(records)
    return len(writable)


def report(task: Task, results: list[Result], verbose: bool) -> None:
    from llm.tasks import validators as V
    clean = [r for r in results if r.text and not r.warnings]
    flagged = [r for r in results if r.text and r.warnings]
    # An empty result with no warnings is not a failure: a proofreading task
    # returns one every time the line was already correct, which is most lines.
    nochange = [r for r in results if not r.text and not r.warnings]
    failed = [r for r in results if not r.text and r.warnings]
    print(f"\n{len(clean)} clean, {len(flagged)} flagged, "
          f"{len(nochange)} no change, {len(failed)} failed  (of {len(results)})")
    tics = V.tics({r.item.key: r.text for r in results if r.text})
    if tics:
        print("\n  stylistic tics across the batch (fix the prompt, not the items):")
        for line in tics:
            print(f"    - {line}")
    if verbose or flagged or failed:
        for result in sorted(flagged + failed, key=lambda r: -r.priority)[:40]:
            print(f"\n  ! {result.item.key}  p={result.priority:.2f}  "
                  f"{', '.join(result.warnings)}")
            print(f"    {result.text[:200]}")
    if verbose:
        for result in clean[:40]:
            print(f"\n  . {result.item.key}  conf={result.confidence}")
            print(f"    {result.text}")


def main(argv: list[str] | None = None) -> int:
    tasks = registry()
    ap = argparse.ArgumentParser(description=__doc__,
                                 formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("task", nargs="?", help="task name (see --list)")
    ap.add_argument("--list", action="store_true", help="list task recipes and exit")
    ap.add_argument("--limit", type=int, default=0, help="only the first N items")
    ap.add_argument("--offset", type=int, default=0)
    ap.add_argument("--apply", action="store_true",
                    help="write to unpacked/ and open a ledger batch (default: dry run)")
    ap.add_argument("--include-flagged", action="store_true",
                    help="apply results that carry validator warnings too")
    ap.add_argument("--concurrency", type=int, default=config.CONCURRENCY)
    ap.add_argument("--no-fallback", action="store_true",
                    help="do not retry failed items on Claude Sonnet")
    ap.add_argument("--max-fallback", type=int, default=fallback.DEFAULT_CAP,
                    help=f"cap Sonnet retries per run (default {fallback.DEFAULT_CAP}); "
                         "this spends your Claude subscription, not a metered key")
    ap.add_argument("--chunk", type=int, default=50,
                    help="with --apply, write to disk every N items (default 50) "
                         "so a long run is visible and interruptible")
    ap.add_argument("--model", default=None, help="override the task's model")
    ap.add_argument("--no-cache", action="store_true")
    ap.add_argument("--verbose", "-v", action="store_true", help="print every generation")
    args = ap.parse_args(argv)

    if args.list or not args.task:
        width = max((len(n) for n in tasks), default=4)
        for name, task in sorted(tasks.items()):
            print(f"{name:<{width}}  [{task.risk:<6}] {task.description}")
        return 0

    task = tasks.get(args.task)
    if not task:
        print(f"unknown task {args.task!r}; known: {', '.join(sorted(tasks))}", file=sys.stderr)
        return 2

    client = Client(args.model or task.model, use_cache=not args.no_cache)
    ok, message = client.health()
    if not ok:
        print(f"gemma box unavailable: {message}", file=sys.stderr)
        return 3
    print(f"{task.name}: {message}\n  model {client.model}")

    budget = None
    if not args.no_fallback and args.max_fallback > 0:
        if fallback.available():
            budget = fallback.Budget(args.max_fallback)
            print(f"  fallback {fallback.SOURCE} for failed items "
                  f"(cap {args.max_fallback})")
        else:
            print("  fallback disabled: `claude` is not on PATH")

    items = task.selector()
    total = len(items)
    print(f"  {total} items need work")
    if args.offset:
        items = items[args.offset:]
    if args.limit:
        items = items[: args.limit]
    if not items:
        print("nothing to do")
        return 0

    # Chunking is what makes a long run watchable and interruptible. Applying
    # only at the very end means a two-hour batch shows nothing at all until it
    # finishes, and a stop at item 940 writes nothing -- the response cache makes
    # a resume cheap, but "cheap" is not "already done".
    chunk_size = args.chunk if args.apply else len(items)
    batch = book = None
    if args.apply:
        batch = ledger.batch_id(task.name)
        book = ledger.Ledger(batch)

    print(f"  generating {len(items)} at concurrency {args.concurrency}"
          + (f", applying every {chunk_size}" if args.apply else "") + "...")
    started = time.monotonic()
    results: list[Result] = []
    seen: dict[str, str] = {}
    written = 0
    try:
        for offset in range(0, len(items), chunk_size):
            chunk = items[offset:offset + chunk_size]
            got = generate(task, client, chunk, args.concurrency, seen,
                           progress=True, budget=budget)
            results.extend(got)
            seen.update({r.item.key: r.text for r in got if r.text})
            if book is not None:
                written += write_chunk(task, client, book, batch, got,
                                       args.include_flagged)
                print(f"  applied {written} of {len(results)} so far "
                      f"({len(items) - len(results)} still to generate)")
    except KeyboardInterrupt:
        print(f"\ninterrupted -- {written} changes already applied and recorded "
              f"in {book.path.name if book else 'nothing'}.\n"
              f"Re-run to continue; the {len(results)} already generated are cached.")
        return 130
    except LLMUnavailable as exc:
        print(f"\nbox went away mid-batch: {exc}\n"
              f"{written} changes applied so far; cached work is kept, "
              f"so re-running resumes cheaply", file=sys.stderr)
        return 3
    elapsed = time.monotonic() - started

    report(task, results, args.verbose)
    print(f"\n{client.usage.summary(elapsed)}  |  {elapsed:.0f}s wall")
    if budget and budget.spent:
        note = " (cap reached -- later failures were left unrecovered)" \
            if budget.spent >= budget.cap else ""
        print(f"  {budget.spent} item(s) recovered by {fallback.SOURCE}{note}")
    if args.limit and results and total > len(items):
        live = max(1, client.usage.calls - client.usage.cached)
        print(f"  extrapolated: the full {total} would take "
              f"{(elapsed / live) * total / 3600:.1f}h")

    if not args.apply:
        print("\ndry run -- nothing written. Re-run with --apply to write.")
        return 0

    if not written:
        print("nothing passed validation; nothing written")
        return 1
    print(f"\napplied {written} changes ({len(results) - written} held back)")
    print(f"ledger: {book.path.relative_to(config.REPO)}")
    print(f"review: python3 bin/llm/ledger.py show {batch} --pending")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
