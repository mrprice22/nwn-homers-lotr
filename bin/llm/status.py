#!/usr/bin/env python3
"""What the harness has done, is doing, and has left to do.

    python3 bin/llm/status.py            # everything
    python3 bin/llm/status.py --watch    # refresh until you stop it

Exists because a long batch is otherwise invisible. `run.py` now applies in
chunks and prints as it goes, but a run started hours ago in another terminal
tells you nothing -- and the first version of this harness applied only at the
very end, so a two-hour run showed an empty `git status` the whole way and
looked exactly like a hang.

Progress for an in-flight run is read from the response cache, which is the one
place a running batch leaves a trace per item rather than per chunk.
"""
from __future__ import annotations

import argparse
import os
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
from llm.client import Client
from llm.tasks import registry


def running() -> list[tuple[int, str]]:
    """In-flight harness processes, as (pid, command)."""
    proc = subprocess.run(["pgrep", "-af", "bin/llm/(run|autopilot)"],
                          capture_output=True, text=True)
    out = []
    for line in proc.stdout.splitlines():
        pid, _, cmd = line.partition(" ")
        if "status.py" in cmd or "pgrep" in cmd:
            continue
        try:
            out.append((int(pid), cmd))
        except ValueError:
            pass
    return out


def proc_start(pid: int) -> float | None:
    """Wall-clock start time of a pid, via /proc uptime arithmetic."""
    try:
        btime = 0.0
        for line in Path("/proc/stat").read_text().splitlines():
            if line.startswith("btime "):
                btime = float(line.split()[1])
                break
        fields = Path(f"/proc/{pid}/stat").read_text().rsplit(") ", 1)[1].split()
        ticks = float(fields[19])                     # starttime, field 22
        return btime + ticks / os.sysconf("SC_CLK_TCK")
    except (OSError, IndexError, ValueError):
        return None


def cache_progress(since: float | None = None) -> tuple[int, float, float] | None:
    """(entries, seconds since first, seconds since last write).

    `since` scopes the count to one run. Without it this counts every cache
    entry ever written -- including earlier dry runs -- and overstates a live
    batch's progress by however much testing preceded it. That is exactly the
    kind of confidently wrong number a status tool must not print.
    """
    if not config.CACHE_DIR.exists():
        return None
    times = [p.stat().st_mtime for p in config.CACHE_DIR.rglob("*.json")]
    if since is not None:
        times = [t for t in times if t >= since]
    if not times:
        return None
    now = time.time()
    return len(times), now - min(times), now - max(times)


def human(seconds: float) -> str:
    if seconds < 90:
        return f"{seconds:.0f}s"
    if seconds < 5400:
        return f"{seconds / 60:.0f}m"
    return f"{seconds / 3600:.1f}h"


def show(skip_selectors: bool = False) -> None:
    client = Client()
    ok, message = client.health()
    print(f"box     : {'up' if ok else 'DOWN'} -- {message}")

    procs = running()
    if procs:
        for pid, cmd in procs:
            print(f"running : pid {pid}  {cmd}")
    else:
        print("running : nothing in flight")

    # Scope to the oldest in-flight run so the count means "this batch", not
    # "everything this cache has ever held".
    since = None
    if procs:
        starts = [s for s in (proc_start(pid) for pid, _ in procs) if s]
        since = min(starts) if starts else None
    cache = cache_progress(since)
    if cache:
        count, age, idle = cache
        rate = count / age if age else 0
        scope = "this run" if since else "all time"
        line = (f"cache   : {count} generations ({scope}), "
                f"{rate * 60:.1f}/min over {human(age)}")
        if procs:
            line += f", last {human(idle)} ago"
            if idle > 300:
                line += "  <-- STALLED?"
        print(line)
        total = cache_progress()
        if since and total and total[0] != count:
            print(f"          ({total[0]} cached in total, including earlier runs)")

    print()
    if skip_selectors:
        print("tasks   : (skipped -- selectors read every blueprint)")
    else:
        print(f"{'task':<15} {'tier':<8} {'outstanding':>12}   description")
        print("-" * 78)
        for name, task in sorted(registry().items()):
            try:
                count = len(task.selector())
                shown = f"{count:,}"
            except SystemExit as exc:
                shown = "n/a"
                task_note = str(exc).splitlines()[0]
                print(f"{name:<15} {task.risk:<8} {shown:>12}   {task_note}")
                continue
            print(f"{name:<15} {task.risk:<8} {shown:>12}   {task.description}")

    print()
    batches = ledger.summary()
    if not batches:
        print("ledger  : nothing recorded yet")
        return
    total = sum(b["total"] for b in batches)
    pending = sum(b["pending"] for b in batches)
    print(f"ledger  : {total} changes in {len(batches)} batch(es), {pending} pending review")
    for b in batches[:8]:
        states = ", ".join(f"{v} {k}" for k, v in sorted(b["states"].items()))
        print(f"          {b['batch']:<34} {b['total']:>5}  ({states})")
    if pending:
        print("\nReview them in the roadmap editor -> LLM Changes, or:")
        print("  python3 bin/llm/ledger.py show <batch> --pending")


def main(argv: list[str] | None = None) -> int:
    ap = argparse.ArgumentParser(description=__doc__,
                                 formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--watch", action="store_true", help="refresh until interrupted")
    ap.add_argument("--interval", type=int, default=60)
    ap.add_argument("--quick", action="store_true",
                    help="skip the per-task counts (they read every blueprint)")
    args = ap.parse_args(argv)

    if not args.watch:
        show(args.quick)
        return 0
    try:
        while True:
            print("\033[2J\033[H", end="")
            print(time.strftime("%H:%M:%S"))
            show(args.quick)
            time.sleep(args.interval)
    except KeyboardInterrupt:
        return 0


if __name__ == "__main__":
    raise SystemExit(main())
