#!/usr/bin/env python3
"""Freeze an archived season's roadmap down to its merit-credit ledger.

Run this ONCE, in an archived season's repo, at Phase 2 of a cutover (see
season-cutover-guide.md §7 step 8). It deletes every `ideas:` entry whose
status is not `awarded`, drops any `epics:` entry left with no children, and
regenerates docs.manual/Roadmap.html.

Why deleting is safe: the backlog is not lost. Everything removed here lives on
in the unnumbered repo's roadmap — which is always the newest season and is the
only place that work will actually get done. What must stay behind is the record
of merit already awarded to players for shipped work, which is exactly the
`awarded` rows. The archived season's roadmap becomes a pure merit ledger, and
the editor never reopens it (there is one backlog, ever — prereq item 12).

Usage:
    python3 bin/roadmap-archive-prune.py            # dry run — report the split
    python3 bin/roadmap-archive-prune.py --apply    # prune + regenerate
    python3 bin/roadmap-archive-prune.py --apply --force   # skip the role guard

Guarded on SEASON_ROLE=archive: this is destructive and only ever correct in a
retired season's repo. Running it in the live/dev repo would delete the entire
working backlog.
"""
from __future__ import annotations

import argparse
import importlib.util
import re
import subprocess
import sys
from collections import Counter
from pathlib import Path

import yaml

REPO = Path(__file__).resolve().parent.parent
YAML_PATH = REPO / "roadmap.yaml"
SERVER_ENV = REPO / "server.env"
GEN = REPO / "bin" / "gen-roadmap.py"

KEEP_STATUS = "awarded"


def load_editor():
    """Reuse the roadmap editor's comment-preserving writer rather than dumping
    the YAML afresh — a plain yaml.dump would flatten every comment in the file
    and reflow all the `notes` block scalars."""
    spec = importlib.util.spec_from_file_location("_rme", REPO / "bin" / "roadmap-editor.py")
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


def season_role() -> str:
    if not SERVER_ENV.exists():
        return ""
    for line in SERVER_ENV.read_text(encoding="utf-8").splitlines():
        m = re.match(r"\s*(?:export\s+)?SEASON_ROLE\s*=\s*(.*)$", line)
        if m:
            val = m.group(1)
            if val[:1] in ('"', "'"):
                return val[1:val.find(val[0], 1)] if val.find(val[0], 1) > 0 else val[1:]
            return re.split(r"\s+#", val, maxsplit=1)[0].strip()
    return ""


def main() -> int:
    ap = argparse.ArgumentParser(description=__doc__,
                                 formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--apply", action="store_true", help="write the pruned file")
    ap.add_argument("--force", action="store_true",
                    help="bypass the SEASON_ROLE=archive guard")
    args = ap.parse_args()

    doc = yaml.safe_load(YAML_PATH.read_text(encoding="utf-8")) or {}
    ideas = doc.get("ideas") or []
    epics = doc.get("epics") or []

    keep = [i for i in ideas if i.get("status") == KEEP_STATUS]
    drop = [i for i in ideas if i.get("status") != KEEP_STATUS]

    kept_epic_ids = {i.get("epic") for i in keep if i.get("epic")}
    epics_keep = [e for e in epics if e.get("id") in kept_epic_ids]
    epics_drop = [e for e in epics if e.get("id") not in kept_epic_ids]

    role = season_role()
    print(f"roadmap.yaml : {len(ideas)} ideas, {len(epics)} epics")
    print(f"season role  : {role or 'unset'}")
    print()
    print(f"KEEP  {len(keep):>4}  status={KEEP_STATUS}")
    print(f"DROP  {len(drop):>4}  everything else:")
    for status, n in Counter(i.get("status", "?") for i in drop).most_common():
        print(f"        {n:>4}  {status}")
    print()
    print(f"epics: keep {len(epics_keep)}, drop {len(epics_drop)} (no awarded children)")
    for e in epics_drop:
        print(f"        - {e.get('id')}: {e.get('title', '')[:60]}")
    print()

    if not args.apply:
        print("DRY RUN — nothing written. Re-run with --apply.")
        return 0

    if role != "archive" and not args.force:
        print("REFUSED: this repo is not an archived season "
              f"(SEASON_ROLE={role or 'unset'}, need 'archive').", file=sys.stderr)
        print("         Pruning the live/dev repo would delete the whole working "
              "backlog.", file=sys.stderr)
        print("         Use --force only if you are certain.", file=sys.stderr)
        return 2

    editor = load_editor()
    editor.write_document(keep, epics=epics_keep)
    print(f"pruned roadmap.yaml -> {len(keep)} ideas, {len(epics_keep)} epics")

    proc = subprocess.run([sys.executable, str(GEN)], cwd=str(REPO))
    if proc.returncode != 0:
        print("WARNING: gen-roadmap.py failed — Roadmap.html is stale", file=sys.stderr)
        return 1
    print()
    print("Next: commit roadmap.yaml + docs.manual/Roadmap.html, then publish to this")
    print("season's roadmapdb so its in-game Recent Updates sign matches the page.")
    return 0


if __name__ == "__main__":
    sys.exit(main())
