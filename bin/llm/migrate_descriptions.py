#!/usr/bin/env python3
"""Move round-one item text from the identified slot to the unidentified one.

    python3 bin/llm/migrate_descriptions.py --dry-run
    python3 bin/llm/migrate_descriptions.py --limit 5
    python3 bin/llm/migrate_descriptions.py

Round one wrote `DescIdentified` under a rule of "never restate the mechanical
bonuses, no numbers of any kind", so what it produced is pure physical
description -- which is what NWN shows for an *unidentified* item. This moves it
to `Description` and empties `DescIdentified`, leaving round two to write the
identified text with the item's properties and their relative standing.

That split is the module's own existing convention, not an invention: 202 items
already pair a short physical unidentified line ("A Glowing Talisman with a
Silver symbol of Paladine") with a lore-rich identified one.

Every write is appended to the ledger, so the move is revertible from the review
panel exactly like any generated change. Risk tier stays `auto`: both fields were
empty before round one, so nothing human-authored is in play.
"""
from __future__ import annotations

import argparse
import sys

if __package__ in (None, ""):
    import pathlib as _pathlib
    _p = str(_pathlib.Path(__file__).resolve().parents[1])
    if _p not in sys.path:
        sys.path.insert(0, _p)

from llm import config, gff, ledger

SOURCE_FIELD = "DescIdentified.value.0"
TARGET_FIELD = "Description.value.0"


def candidates(task: str = "item_desc") -> list[dict]:
    """Ledger records still holding round-one text in the identified slot."""
    out = []
    for rec in ledger.read_all():
        if rec.get("task") != task or rec.get("field") != SOURCE_FIELD:
            continue
        if rec.get("review") == "reverted":
            continue        # already undone; nothing to move
        out.append(rec)
    return out


def main(argv: list[str] | None = None) -> int:
    ap = argparse.ArgumentParser(description=__doc__,
                                 formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--task", default="item_desc")
    ap.add_argument("--limit", type=int, default=0)
    ap.add_argument("--dry-run", action="store_true")
    args = ap.parse_args(argv)

    records = candidates(args.task)
    if args.limit:
        records = records[: args.limit]
    if not records:
        print("nothing to move")
        return 0

    print(f"{len(records)} item(s) to move: {SOURCE_FIELD} -> {TARGET_FIELD}")
    if args.dry_run:
        for rec in records[:5]:
            print(f"  {rec['file']}: {str(rec['after'])[:70]}...")
        print(f"  ... and {max(0, len(records) - 5)} more (dry run, nothing written)")
        return 0

    batch = ledger.batch_id("desc_to_unidentified")
    book = ledger.Ledger(batch)
    moved = skipped = 0
    changes: list[ledger.Change] = []

    for rec in records:
        path = config.REPO / rec["file"]
        if not path.exists():
            print(f"  !! missing {rec['file']}")
            skipped += 1
            continue
        data = gff.load(path)
        current = gff.read_path(data, SOURCE_FIELD)
        if current != rec["after"]:
            # Someone edited this since generation. Their text is not ours to
            # relocate, so leave it exactly where it is.
            print(f"  .. {rec['file']} changed since generation, left alone")
            skipped += 1
            continue

        before_target = gff.read_path(data, TARGET_FIELD)
        gff.write_path(data, TARGET_FIELD, current)
        gff.write_path(data, SOURCE_FIELD, None)
        gff.dump(path, data)
        moved += 1

        common = dict(file=rec["file"], task="desc_to_unidentified", risk="auto",
                      batch=batch, source=rec.get("source", "gemma"),
                      review="pending", prompt_version=rec.get("prompt_version", 1))
        changes.append(ledger.Change(field=TARGET_FIELD, before=before_target,
                                     after=current, **common))
        changes.append(ledger.Change(field=SOURCE_FIELD, before=current,
                                     after=None, **common))

    book.extend(changes)
    print(f"\nmoved {moved}, skipped {skipped}")
    print(f"ledger: {book.path.relative_to(config.REPO)} ({len(changes)} records)")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
