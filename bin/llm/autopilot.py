#!/usr/bin/env python3
"""Unattended loop: let the local model work the content backlog on its own.

    python3 bin/llm/autopilot.py --once --dry-run     # see what it would do
    python3 bin/llm/autopilot.py --once               # one batch, committed
    python3 bin/llm/autopilot.py                      # until the queues empty

One cycle is: pick the highest-priority task with work outstanding, generate a
bounded batch, validate, apply what passes, run the build gates, commit, push,
and append a line to llm-changes/INBOX.md.

Three constraints shape all of it.

**The scope fence.** This model writes prose and classifies things. It never
writes NWScript, never edits GFF structure, never touches .git.json placements
or roadmap status/merit fields. It cannot check whether an NWScript function
exists -- inventing plausible builtins is its characteristic failure -- and a
build gate would not catch a script that compiles and does nothing. Every task
it may run is declared in TASKS below; there is no "and anything else" branch.

**The gate it can actually run.** `tests/smoke-test` is pure Python over the
repo and needs no NWN tooling, so this can run it before every commit. Full
`nwn-manager repack` needs nasher and the script compiler and stays a human
step -- which is sound, because nothing here touches a script.

**It is not the only writer.** The wiki refresh and the roadmap editor both
commit this tree on their own schedule. So: never `git add -A`, only the paths
this run touched; take an advisory lock; and rebase before pushing.
"""
from __future__ import annotations

import argparse
import fcntl
import subprocess
import sys
import time
from pathlib import Path

if __package__ in (None, ""):
    import pathlib as _pathlib
    _p = str(_pathlib.Path(__file__).resolve().parents[1])
    if _p not in sys.path:
        sys.path.insert(0, _p)

from llm import config, ledger
from llm.client import Client, LLMUnavailable
from llm.run import generate
from llm.tasks import registry

# The allowlist. A task not named here never runs unattended, whatever its
# recipe says -- adding a task to bin/llm/tasks/ must not silently arm it.
# NB: filling in blank `Comment`/`Comments` fields on anything in unpacked/ was
# considered and explicitly ruled out (2026-08-23). Those are builder notes, not
# content -- generating them adds noise to the toolset without telling a builder
# anything they could not read off the area itself.
TASKS = ("item_desc", "creature_desc")

BATCH_SIZE = 60           # small enough that a bad prompt costs one batch
INBOX = "llm-changes/INBOX.md"


class Busy(RuntimeError):
    pass


class Lock:
    """Advisory lock so two autopilot runs cannot interleave commits."""

    def __init__(self, path: Path):
        self.path = path
        self.handle = None

    def __enter__(self):
        self.handle = self.path.open("a+")
        try:
            fcntl.flock(self.handle, fcntl.LOCK_EX | fcntl.LOCK_NB)
        except OSError as exc:
            self.handle.close()
            raise Busy(f"another autopilot run holds {self.path}") from exc
        return self

    def __exit__(self, *exc):
        fcntl.flock(self.handle, fcntl.LOCK_UN)
        self.handle.close()


def git(*args: str, check: bool = True) -> subprocess.CompletedProcess:
    proc = subprocess.run(["git", "-C", str(config.REPO), *args],
                          capture_output=True, text=True)
    if check and proc.returncode:
        raise RuntimeError(f"git {' '.join(args)} failed: {proc.stderr.strip()}")
    return proc


def gates() -> tuple[bool, str]:
    """The build gates this host can run without NWN tooling."""
    smoke = config.REPO / "tests" / "smoke-test"
    if not smoke.exists():
        return True, "no tests/smoke-test on this checkout -- skipped"
    proc = subprocess.run(["bash", str(smoke)], capture_output=True, text=True,
                          cwd=str(config.REPO))
    tail = "\n".join((proc.stdout + proc.stderr).strip().splitlines()[-15:])
    return proc.returncode == 0, tail


def note_inbox(lines: list[str]) -> None:
    """Append a run summary for whoever (or whatever) reads it next.

    The point of the file is that a coding agent picking this repo up later can
    see what the local model did without replaying any of it.
    """
    path = config.REPO / INBOX
    path.parent.mkdir(parents=True, exist_ok=True)
    if not path.exists():
        path.write_text(
            "# LLM harness inbox\n\n"
            "Appended by `bin/llm/autopilot.py` after every run. Newest last.\n"
            "Review the changes themselves in the roadmap editor's "
            "**LLM Changes** panel, or with `python3 bin/llm/ledger.py list`.\n",
            encoding="utf-8")
    with path.open("a", encoding="utf-8") as fh:
        fh.write("\n## " + time.strftime("%Y-%m-%d %H:%M") + "\n")
        for line in lines:
            fh.write(f"- {line}\n")


def pick(client: Client) -> tuple[str, list] | None:
    """Highest-priority task with outstanding work. Order is TASKS order."""
    tasks = registry()
    for name in TASKS:
        task = tasks.get(name)
        if not task:
            continue
        try:
            items = task.selector()
        except SystemExit as exc:          # a missing module-index, usually
            print(f"  {name}: skipped ({exc})")
            continue
        if items:
            return name, items
    return None


def cycle(dry_run: bool, batch_size: int, concurrency: int) -> bool:
    """One task batch. Returns True if there may be more work."""
    client = Client()
    ok, message = client.health()
    if not ok:
        print(f"gemma box unavailable: {message}")
        return False

    chosen = pick(client)
    if not chosen:
        print("no task has outstanding work")
        return False
    name, items = chosen
    task = registry()[name]
    todo = items[:batch_size]
    print(f"{name}: {len(items)} outstanding, taking {len(todo)}")

    if dry_run:
        for item in todo[:5]:
            print(f"  would write {item.field} in {item.path.name}")
        print(f"  ... and {max(0, len(todo) - 5)} more (dry run, nothing written)")
        return False

    started = time.monotonic()
    results = generate(task, client, todo, concurrency, progress=True)
    elapsed = time.monotonic() - started
    writable = [r for r in results if r.text and not r.warnings]
    held = len(results) - len(writable)
    if not writable:
        print("nothing passed validation; stopping rather than looping on a bad prompt")
        return False

    batch = ledger.batch_id(task.name)
    book = ledger.Ledger(batch)
    touched: set[str] = set()
    records = []
    for result in writable:
        task.apply(result)
        rel = str(result.item.path.relative_to(config.REPO))
        touched.add(rel)
        records.append(ledger.Change(
            file=rel, field=result.item.field, before=result.item.before,
            after=result.text, task=task.name, risk=task.risk, batch=batch,
            source=client.short_name, review="pending", priority=result.priority,
            warnings=result.warnings, confidence=result.confidence,
            prompt_version=task.prompt_version))
    book.extend(records)

    passed, tail = gates()
    if not passed:
        print("BUILD GATES FAILED -- rolling the batch back, nothing committed")
        print(tail)
        for record in records:
            try:
                ledger.revert(record.id)
            except Exception as exc:  # noqa: BLE001
                print(f"  could not revert {record.file}: {exc}")
        note_inbox([f"**{name}: gates failed**, {len(records)} changes rolled back.",
                    "```", tail, "```"])
        return False

    paths = sorted(touched) + [str(book.path.relative_to(config.REPO)), INBOX]
    note_inbox([
        f"`{name}`: wrote {len(writable)} of {len(results)} "
        f"({held} held back by validators) in {elapsed / 60:.0f} min.",
        f"{len(items) - len(writable)} items of this task still outstanding.",
        f"Review: roadmap editor -> **LLM Changes**, batch `{batch}`.",
    ])
    git("add", "--", *paths)
    if not git("diff", "--cached", "--quiet", check=False).returncode:
        print("nothing staged; skipping commit")
        return True
    message_body = (
        f"{name}: {len(writable)} generated descriptions\n\n"
        f"Written by the local Gemma model via bin/llm/autopilot.py and gated on\n"
        f"tests/smoke-test. Every change is revertible from the roadmap editor's\n"
        f"LLM Changes panel.\n\n"
        f"LLM-Batch: {batch}\n"
        f"Co-Authored-By: Gemma (local) <noreply@localhost>\n"
    )
    git("commit", "-m", message_body)
    sha = git("rev-parse", "HEAD").stdout.strip()
    book.stamp_commit(sha)
    git("add", "--", str(book.path.relative_to(config.REPO)))
    git("commit", "--amend", "--no-edit")
    print(f"committed {sha[:10]}: {len(writable)} changes")

    push = git("push", check=False)
    if push.returncode:
        print(f"push failed ({push.stderr.strip()}); rebasing and retrying")
        git("pull", "--rebase", "--autostash", check=False)
        push = git("push", check=False)
        if push.returncode:
            print("push still failing -- the commit is local, resolve by hand")
    return True


def main(argv: list[str] | None = None) -> int:
    ap = argparse.ArgumentParser(description=__doc__,
                                 formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--once", action="store_true", help="one batch, then stop")
    ap.add_argument("--dry-run", action="store_true",
                    help="report what would be done; write and commit nothing")
    ap.add_argument("--batch-size", type=int, default=BATCH_SIZE)
    ap.add_argument("--concurrency", type=int, default=config.CONCURRENCY)
    ap.add_argument("--max-cycles", type=int, default=0, help="0 = until empty")
    args = ap.parse_args(argv)

    try:
        with Lock(config.LOCK_PATH):
            if not args.dry_run:
                git("pull", "--rebase", "--autostash", check=False)
            cycles = 0
            while True:
                cycles += 1
                try:
                    more = cycle(args.dry_run, args.batch_size, args.concurrency)
                except LLMUnavailable as exc:
                    print(f"box went away: {exc}")
                    return 3
                if args.once or not more:
                    break
                if args.max_cycles and cycles >= args.max_cycles:
                    print(f"stopping after {cycles} cycles as asked")
                    break
    except Busy as exc:
        print(exc)
        return 4
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
