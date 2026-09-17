#!/usr/bin/env python3
"""Move shipped roadmap items to `deployed` once their code reaches production.

The lifecycle splits "shipped to the test realm" from "deployed to the live
season":

    ... -> confirmed -> manual -> implemented -> deployed
                                       ^             ^
                                  merit is paid   nobody clicks this

`implemented` is a decision somebody makes; `deployed` is a FACT about git, and
a fact nobody should have to maintain by hand. So it is computed here, from the
same per-idea environment badge the editor's list and board already show
(CLAUDE-roadmap.md, "The per-idea environment badge"): an item is deployed when
every sha in its `commit:` field is an ancestor of the last promoted dev commit.

This script is deliberately the only writer of that transition, and it is:

  * FORWARD ONLY. It promotes `implemented` -> `deployed` and nothing else. It
    never demotes, never touches `manual`, and never writes `merit_awarded` or
    `uat_credits` -- those record real payments into meritdb and are the
    editor's buttons' business alone.
  * CONSERVATIVE. Only the unambiguous `live` state moves. An item with both a
    promoted and an unpromoted commit (`rework`), one whose commit resolves
    nowhere (`missing`), one with no `commit:` at all (`untracked`) and one that
    lives in nwn_manager (`external`) are all left where they are and listed, so
    the ambiguity stays visible instead of being decided by a script.
  * IDEMPOTENT, and safe to run from anything. A second run is a no-op.
  * NEVER FATAL. If no promotion baseline can be resolved (no live sibling repo,
    no promote/* tag) it says so and exits 0: it runs inside season-promote.sh
    and inside the nightly wiki refresh, and neither may fail over a badge.

Callers:

    bin/season-promote.sh          --base <dev sha> --apply, BEFORE the rsync,
                                   so the new statuses ride the promotion into
                                   the season repo
    bin/refresh-homers-lotr-wiki   --apply, as the catch-up path for promotions
                                   that happened out of band
                                   (lives in the nwn_manager repo)

Usage:

    python3 bin/roadmap-reconcile-deployed.py                 # dry run, report
    python3 bin/roadmap-reconcile-deployed.py --apply
    python3 bin/roadmap-reconcile-deployed.py --base <ref> --apply
    python3 bin/roadmap-reconcile-deployed.py --migrate-awarded --apply

`--migrate-awarded` is the one-shot for the rename that introduced this script.
`awarded` meant "done, nothing outstanding", and most of those rows predate the
`commit:` convention, so there is nothing to prove them with either way: each
one keeps its terminal position (`deployed`) unless the badge positively says
its code is still only on the test realm, in which case it lands honestly at
`implemented`. `merit_awarded` is preserved either way -- it is the record of a
payment, and this script never has an opinion about payments.

Writing goes through bin/roadmap-apply-patch.py's own apply_patch(), under the
editor's file lock, so the admin can be editing another item in the GUI while
this runs.
"""
from __future__ import annotations

import argparse
import importlib.util
import sys
from pathlib import Path

REPO = Path(__file__).resolve().parent.parent
YAML_PATH = REPO / "roadmap.yaml"

SHIPPED_TO_TEST = "implemented"
DEPLOYED = "deployed"
LEGACY_AWARDED = "awarded"


def _load(name: str, path: Path):
    spec = importlib.util.spec_from_file_location(name, path)
    mod = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(mod)
    return mod


def main() -> int:
    ap = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    ap.add_argument("--apply", action="store_true",
                    help="write roadmap.yaml (default: dry run)")
    ap.add_argument("--base", metavar="REF",
                    help="treat REF as the last promoted commit, instead of "
                         "resolving it from the live season repo or a "
                         "promote/* tag. season-promote.sh passes the sha it "
                         "is about to promote, so the statuses are already "
                         "right when the tree is copied.")
    ap.add_argument("--migrate-awarded", action="store_true",
                    help="one-shot: also rewrite the legacy `awarded` status "
                         "to `deployed` or `implemented`, whichever is true")
    args = ap.parse_args()

    rel = _load("gen_release_notes", REPO / "bin" / "gen-release-notes.py")
    ed = _load("ed", REPO / "bin" / "roadmap-editor.py")
    patcher = _load("apply_patch_mod", REPO / "bin" / "roadmap-apply-patch.py")
    import yaml

    doc = yaml.load(YAML_PATH.read_text(encoding="utf-8"), Loader=ed._YamlLoader)
    ideas = doc.get("ideas") or []

    # A badge is never worth failing a promotion or a nightly refresh over --
    # same rule environment_map() follows in the editor.
    try:
        index = rel.promotion_index(since=args.base)
    except SystemExit as e:
        print(f"[skip] no promotion baseline: {e}")
        return 0
    except Exception as e:                                # pragma: no cover
        print(f"[skip] could not read the promotion index: {e}")
        return 0
    print(f"baseline: {index['base'][:11]}  ({index['provenance']})")

    patch: dict[str, dict] = {}
    held: list[tuple[str, str, str]] = []
    for idea in ideas:
        iid, status = idea.get("id"), idea.get("status")
        if not iid:
            continue
        legacy = args.migrate_awarded and status == LEGACY_AWARDED
        if status != SHIPPED_TO_TEST and not legacy:
            continue
        # classify_idea() asks PUB.is_shipped(), and `awarded` is no longer a
        # shipped status -- so a legacy row would come back "Reopened after
        # release" for the very commits that prove it IS released. Classify the
        # migration against what the row is about to become.
        probe = dict(idea, status=DEPLOYED) if legacy else idea
        state, why = rel.classify_idea(probe, index)
        if legacy:
            # `awarded` meant "done, nothing left" and most of these predate the
            # `commit:` convention entirely, so an unprovable row keeps the
            # terminal position it already had. Only positive evidence that the
            # code is still ONLY on the test realm demotes it.
            want = (SHIPPED_TO_TEST
                    if state in (rel.ENV_DEV, rel.ENV_REWORK) else DEPLOYED)
        elif state == rel.ENV_LIVE:
            want = DEPLOYED
        else:
            held.append((iid, rel.ENV_LABELS.get(state, state or "?"), why))
            continue
        if want != status:
            patch[iid] = {"status": want}
            print(f"  {status:>12} -> {want:<10} {iid}")

    if held:
        print(f"\nheld at `{SHIPPED_TO_TEST}` ({len(held)}) — not unambiguously "
              f"in production:")
        for iid, label, why in held:
            print(f"  {label:<24} {iid}" + (f"  ({why})" if why else ""))

    if not patch:
        print("\nnothing to do.")
        return 0
    print(f"\n{len(patch)} idea(s) to move.")
    if not args.apply:
        print("dry run — re-run with --apply to write roadmap.yaml.")
        return 0

    with ed.yaml_lock(timeout=60.0):
        return patcher.apply_patch(ed, yaml, YAML_PATH, patch, dry=False)


if __name__ == "__main__":
    sys.exit(main())
