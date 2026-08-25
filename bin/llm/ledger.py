"""The change ledger: an auditable, revertible record of every generated edit.

One JSONL file per batch under `llm-changes/`, committed alongside the change
it describes. One record per atomic field write, so a revert is just "write
`before` back" -- precise, independent of git history, and still correct after
later commits have touched the same file.

Risk tiers are assigned by the *task recipe*, deterministically. They are never
inferred by asking a model: that would cost tokens, vary run to run, and put the
safety decision in the hands of the thing being guarded.

    auto    new text into a previously EMPTY field. Nothing human-authored is
            destroyed, so it is applied straight to unpacked/.
    review  MODIFIES existing human-written text, or is player-facing prose.
            Applied, but surfaced in the editor's review panel first.
    hold    never auto-applied: any .nss, any GFF structure, .git.json
            placements, roadmap status/merit_awarded/uat_credits.
"""
from __future__ import annotations

import json
import os
import subprocess
import time
import uuid
from dataclasses import asdict, dataclass, field
from pathlib import Path
from typing import Any, Iterator

# Importable both as `python3 -m llm.<mod>` and as `python3 bin/llm/<mod>.py`,
# which is how every other tool in bin/ is invoked.
if __package__ in (None, ""):
    import pathlib as _pathlib
    import sys as _sys
    _sys.path.insert(0, str(_pathlib.Path(__file__).resolve().parents[1]))

from llm import config, gff

RISKS = ("auto", "review", "hold")
REVIEW_STATES = ("pending", "approved", "edited", "reverted")


@dataclass
class Change:
    file: str                      # repo-relative
    field: str                     # dotted path, see gff.write_path
    before: Any
    after: Any
    task: str
    risk: str
    batch: str
    source: str                    # "gemma:12B", "claude", "human"
    id: str = field(default_factory=lambda: uuid.uuid4().hex[:12])
    review: str = "pending"
    priority: float = 0.0          # higher = look at this first
    warnings: list[str] = field(default_factory=list)
    confidence: float | None = None
    prompt_version: int = 1
    commit: str | None = None
    ts: str = field(default_factory=lambda: time.strftime("%Y-%m-%dT%H:%M:%S"))
    note: str | None = None

    def __post_init__(self) -> None:
        if self.risk not in RISKS:
            raise ValueError(f"unknown risk tier {self.risk!r}, expected one of {RISKS}")


def batch_id(task: str) -> str:
    return f"{task}-{time.strftime('%Y%m%d-%H%M%S')}"


def path_for(batch: str) -> Path:
    return config.LEDGER_DIR / f"{batch}.jsonl"


class Ledger:
    """Append-only writer for one batch."""

    def __init__(self, batch: str):
        self.batch = batch
        self.path = path_for(batch)
        self.path.parent.mkdir(parents=True, exist_ok=True)

    def append(self, change: Change) -> None:
        with self.path.open("a", encoding="utf-8") as fh:
            fh.write(json.dumps(asdict(change), ensure_ascii=False) + "\n")

    def extend(self, changes: list[Change]) -> None:
        if not changes:
            return
        with self.path.open("a", encoding="utf-8") as fh:
            for change in changes:
                fh.write(json.dumps(asdict(change), ensure_ascii=False) + "\n")

    def stamp_commit(self, sha: str) -> None:
        """Backfill `commit` on every record, once the batch has been committed."""
        rewrite(self.path, lambda rec: {**rec, "commit": rec.get("commit") or sha})


# -- reading --------------------------------------------------------------
def batches() -> list[Path]:
    if not config.LEDGER_DIR.exists():
        return []
    return sorted(config.LEDGER_DIR.glob("*.jsonl"), reverse=True)


def read(path: Path) -> Iterator[dict]:
    with path.open(encoding="utf-8") as fh:
        for line in fh:
            line = line.strip()
            if line:
                yield json.loads(line)


def read_all() -> list[dict]:
    """Every record, newest batch first, with `_batch_file` added for writes back."""
    out: list[dict] = []
    for path in batches():
        for rec in read(path):
            rec["_batch_file"] = path.name
            out.append(rec)
    return out


def find(change_id: str) -> tuple[Path, dict] | None:
    for path in batches():
        for rec in read(path):
            if rec.get("id") == change_id:
                return path, rec
    return None


def rewrite(path: Path, fn) -> None:
    """Rewrite a ledger file through `fn(record) -> record`, atomically."""
    records = [fn(rec) for rec in read(path)]
    tmp = path.with_suffix(".jsonl.tmp")
    with tmp.open("w", encoding="utf-8") as fh:
        for rec in records:
            rec.pop("_batch_file", None)
            fh.write(json.dumps(rec, ensure_ascii=False) + "\n")
    os.replace(tmp, path)


# -- applying, reverting, editing -----------------------------------------
def apply_change(change: Change | dict, repo: Path | None = None) -> None:
    """Write `after` into the target file."""
    rec = change if isinstance(change, dict) else asdict(change)
    target = (repo or config.REPO) / rec["file"]
    data = gff.load(target)
    gff.write_path(data, rec["field"], rec["after"])
    gff.dump(target, data)


def revert(change_id: str, repo: Path | None = None) -> dict:
    """Restore `before` on disk and mark the record reverted."""
    found = find(change_id)
    if not found:
        raise KeyError(f"no ledger record {change_id!r}")
    path, rec = found
    target = (repo or config.REPO) / rec["file"]
    data = gff.load(target)
    gff.write_path(data, rec["field"], rec["before"])
    gff.dump(target, data)
    _set_state(path, change_id, "reverted")
    return rec


def edit(change_id: str, text: str, repo: Path | None = None) -> dict:
    """Replace the generated text with a human's, on disk and in the ledger."""
    found = find(change_id)
    if not found:
        raise KeyError(f"no ledger record {change_id!r}")
    path, rec = found
    target = (repo or config.REPO) / rec["file"]
    data = gff.load(target)
    gff.write_path(data, rec["field"], text)
    gff.dump(target, data)
    rewrite(path, lambda r: {**r, "after": text, "review": "edited",
                             "source": r["source"] + "+human"} if r.get("id") == change_id else r)
    return rec


def approve(change_id: str) -> dict:
    found = find(change_id)
    if not found:
        raise KeyError(f"no ledger record {change_id!r}")
    path, rec = found
    _set_state(path, change_id, "approved")
    return rec


def approve_many(change_ids: list[str]) -> int:
    """Bulk-approve. Grouped by file so each ledger is rewritten once."""
    wanted = set(change_ids)
    count = 0
    for path in batches():
        ids_here = {r["id"] for r in read(path)} & wanted
        if not ids_here:
            continue
        count += len(ids_here)
        rewrite(path, lambda r: {**r, "review": "approved"} if r.get("id") in ids_here else r)
    return count


def _set_state(path: Path, change_id: str, state: str) -> None:
    if state not in REVIEW_STATES:
        raise ValueError(f"unknown review state {state!r}")
    rewrite(path, lambda r: {**r, "review": state} if r.get("id") == change_id else r)


# -- summaries ------------------------------------------------------------
def summary() -> list[dict]:
    """Per-batch rollup for the review panel."""
    out = []
    for path in batches():
        recs = list(read(path))
        if not recs:
            continue
        states: dict[str, int] = {}
        for rec in recs:
            states[rec.get("review", "pending")] = states.get(rec.get("review", "pending"), 0) + 1
        out.append({
            "batch": recs[0].get("batch", path.stem),
            "file": path.name,
            "task": recs[0].get("task"),
            "risk": recs[0].get("risk"),
            "source": recs[0].get("source"),
            "ts": recs[0].get("ts"),
            "commit": recs[0].get("commit"),
            "total": len(recs),
            "states": states,
            "pending": states.get("pending", 0),
        })
    return out


def _git(*args: str) -> str:
    return subprocess.run(["git", "-C", str(config.REPO), *args],
                          capture_output=True, text=True, check=False).stdout.strip()


# -- CLI ------------------------------------------------------------------
def main(argv: list[str] | None = None) -> int:
    import argparse

    ap = argparse.ArgumentParser(
        description="Query and act on the local-LLM change ledger. "
                    "Also the recording path for an agent's own bulk content edits.")
    sub = ap.add_subparsers(dest="cmd", required=True)

    sub.add_parser("list", help="per-batch summary")

    p_show = sub.add_parser("show", help="records in one batch")
    p_show.add_argument("batch")
    p_show.add_argument("--pending", action="store_true")

    p_rec = sub.add_parser("record", help="record a change already made by hand or by an agent")
    p_rec.add_argument("--batch", required=True)
    p_rec.add_argument("--task", required=True)
    p_rec.add_argument("--file", required=True)
    p_rec.add_argument("--field", required=True)
    p_rec.add_argument("--before", default=None)
    p_rec.add_argument("--after", required=True)
    p_rec.add_argument("--risk", default="review", choices=RISKS)
    p_rec.add_argument("--source", default="claude")

    p_rev = sub.add_parser("revert", help="restore `before` on disk")
    p_rev.add_argument("change_id")

    p_app = sub.add_parser("approve", help="mark reviewed")
    p_app.add_argument("change_id")

    p_stamp = sub.add_parser("stamp", help="backfill the commit sha on a batch")
    p_stamp.add_argument("batch")
    p_stamp.add_argument("--sha", default=None)

    args = ap.parse_args(argv)

    if args.cmd == "list":
        rows = summary()
        if not rows:
            print("no batches yet")
            return 0
        for row in rows:
            print(f"{row['batch']:<36} {row['task']:<16} {row['risk']:<7} "
                  f"{row['total']:>5} changes  {row['pending']:>5} pending  {row['ts']}")
        return 0

    if args.cmd == "show":
        path = path_for(args.batch)
        if not path.exists():
            print(f"no such batch: {args.batch}")
            return 1
        for rec in read(path):
            if args.pending and rec.get("review") != "pending":
                continue
            print(f"{rec['id']}  {rec['review']:<9} p={rec.get('priority', 0):.2f}  {rec['file']}")
            print(f"    - {rec.get('before')!r}")
            print(f"    + {rec.get('after')!r}")
            if rec.get("warnings"):
                print(f"    ! {', '.join(rec['warnings'])}")
        return 0

    if args.cmd == "record":
        change = Change(file=args.file, field=args.field, before=args.before,
                        after=args.after, task=args.task, risk=args.risk,
                        batch=args.batch, source=args.source)
        Ledger(args.batch).append(change)
        print(change.id)
        return 0

    if args.cmd == "revert":
        rec = revert(args.change_id)
        print(f"reverted {args.change_id} in {rec['file']}")
        return 0

    if args.cmd == "approve":
        approve(args.change_id)
        print(f"approved {args.change_id}")
        return 0

    if args.cmd == "stamp":
        sha = args.sha or _git("rev-parse", "HEAD")
        Ledger(args.batch).stamp_commit(sha)
        print(f"stamped {args.batch} with {sha}")
        return 0

    return 1


if __name__ == "__main__":
    raise SystemExit(main())
