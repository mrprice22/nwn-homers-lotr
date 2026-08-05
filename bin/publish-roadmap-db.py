#!/usr/bin/env python3
"""Push roadmap.yaml's shipped work into the in-game Recent Updates sign DB.

The headless half of the roadmap editor's "Publish to Wiki & DB" button. Before
this existed the in-game sign could only be refreshed by a human clicking that
button, so anything shipped by an agent or a hand-edit left the board stale
while the website moved on. bin/refresh-homers-lotr-wiki calls this on the daily
cycle; run it by hand whenever you want the sign current right now.

    python3 bin/publish-roadmap-db.py --dry-run   # show what would be written
    python3 bin/publish-roadmap-db.py             # write roadmapdb

No restart needed — the server reads the campaign DB on each use of the sign.
"""
from __future__ import annotations

import argparse
import importlib.util
import sys
from pathlib import Path

REPO = Path(__file__).resolve().parent.parent
sys.path.insert(0, str(REPO / "bin"))

import roadmap_publish as PUB  # noqa: E402

import yaml  # noqa: E402


def main() -> int:
    ap = argparse.ArgumentParser(description=__doc__,
                                 formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--dry-run", action="store_true",
                    help="print the per-bucket row counts and headlines, write nothing")
    args = ap.parse_args()

    doc = yaml.safe_load(PUB.YAML_PATH.read_text(encoding="utf-8")) or {}
    ideas = doc.get("ideas") or []
    errs = PUB.GEN.validate(doc)
    if errs:
        print("roadmap.yaml is invalid — refusing to publish:", file=sys.stderr)
        for e in errs:
            print(f"  {e}", file=sys.stderr)
        return 1

    if args.dry_run:
        buckets = PUB.build_rows(ideas, doc.get("groups"), doc.get("epics"))
        for bucket, rows in buckets.items():
            print(f"\n=== {bucket}  ({len(rows)} row(s)) ===")
            for rank, r in enumerate(rows):
                print(f"  {rank:>3}  {r[4] or '(no date)':<10}  {r[1]}{r[0]}")
        print(f"\nWould write to {PUB.recent_db_path()} (dry run).")
        return 0

    ok, msg = PUB.sync_recent_updates_db(ideas, doc.get("groups"),
                                         doc.get("epics"))
    print(msg)
    return 0 if ok else 1


if __name__ == "__main__":
    sys.exit(main())
