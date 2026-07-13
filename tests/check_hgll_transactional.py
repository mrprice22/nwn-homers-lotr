#!/usr/bin/env python3
"""Legendary-leveler transaction check (build-time smoke test).

The HGLL leveler (hgll_dlg_leveler) must stage every pick and touch the character
only once, from HGLL_CommitLevelUp, when the player confirms on the final page.

This used to be an exploit: each pick was applied the moment it was confirmed, but
the level itself was only consumed at the end, so backing out of the last
confirmation ("No. I want to start over.") — or just walking away — kept the skill
ranks, feat and ability point while leaving the player eligible to level again.
Players farmed unlimited skills, feats and stats that way.

Guards the invariants that keep it closed:
  1. hgll_dlg_leveler applies nothing directly — no HGLL_Add*/ModifySaves/
     SetDocumentedLevel calls, only HGLL_CommitLevelUp.
  2. Staged picks are dropped on every exit path: the dialog's CleanUp (DLG_ABORT /
     DLG_END), the leveler's entry point, and logout.
  3. GetIsSkillAvailable still adds the staged points to the live rank, or the
     per-skill cap would not bind until the level was committed.

Scans unpacked/ directly. Exits 0 on success, 1 on any failure.
"""

import os
import re
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
UNPACKED = os.path.join(ROOT, "unpacked")

# Mutating helpers from hgll_leto_inc. The dialog must call none of them directly.
APPLY_FUNCS = [
    "HGLL_AddSkillPoint",
    "HGLL_AddFeat",
    "HGLL_AddStatPoint",
    "HGLL_AddHitPoints",
    "HGLL_ModifySaves",
    "HGLL_SetDocumentedLevel",
]

failures = []


def read(name):
    with open(os.path.join(UNPACKED, name), encoding="utf-8") as f:
        return f.read()


def strip_comments(src):
    src = re.sub(r"/\*.*?\*/", "", src, flags=re.S)
    return re.sub(r"//[^\n]*", "", src)


def calls(src, func):
    return re.search(r"\b%s\s*\(" % re.escape(func), src) is not None


leveler = strip_comments(read("hgll_dlg_leveler.nss"))
funcs = strip_comments(read("hgll_func_inc.nss"))
start = strip_comments(read("hgll_start_dlg.nss"))
exit_ = strip_comments(read("hgll_client_exit.nss"))

# 1. the dialog stages, it does not apply
for func in APPLY_FUNCS:
    if calls(leveler, func):
        failures.append(
            "hgll_dlg_leveler.nss calls %s() directly — picks must be staged and "
            "applied only by HGLL_CommitLevelUp on the final confirmation" % func
        )

if not calls(leveler, "HGLL_CommitLevelUp"):
    failures.append("hgll_dlg_leveler.nss never calls HGLL_CommitLevelUp()")

for func in ("HGLL_AddPendingSkillPoint", "HGLL_SetPendingFeat", "HGLL_SetPendingStat"):
    if not calls(leveler, func):
        failures.append("hgll_dlg_leveler.nss never calls %s() — picks are not staged" % func)

# The commit must apply everything the level-up grants, exactly once.
commit = re.search(
    r"void\s+HGLL_CommitLevelUp\s*\([^)]*\)\s*\{(.*?)\n\}", funcs, flags=re.S
)
if not commit:
    failures.append("hgll_func_inc.nss does not define HGLL_CommitLevelUp()")
else:
    body = commit.group(1)
    for func in APPLY_FUNCS:
        if not calls(body, func):
            failures.append("HGLL_CommitLevelUp() does not apply %s()" % func)
    if not calls(body, "HGLL_FlushChanges"):
        failures.append("HGLL_CommitLevelUp() does not call HGLL_FlushChanges()")
    if not calls(body, "HGLL_ClearPendingPicks"):
        failures.append("HGLL_CommitLevelUp() does not clear the staged picks")

# 2. every exit path drops the staged picks
cleanup = re.search(r"void\s+CleanUp\s*\(\s*\)\s*\{(.*?)\n\}", leveler, flags=re.S)
if not cleanup:
    failures.append("hgll_dlg_leveler.nss does not define CleanUp()")
elif not calls(cleanup.group(1), "HGLL_ClearPendingPicks"):
    failures.append(
        "CleanUp() does not call HGLL_ClearPendingPicks() — aborting the conversation "
        "would leave staged picks on the PC"
    )

if not calls(leveler, "HGLL_ResetLevelUpSession"):
    failures.append(
        "hgll_dlg_leveler.nss never calls HGLL_ResetLevelUpSession() — 'No. I want to "
        "start over.' must discard the staged picks"
    )

if not calls(start, "HGLL_ClearPendingPicks"):
    failures.append(
        "hgll_start_dlg.nss does not call HGLL_ClearPendingPicks() — staged picks left "
        "by an interrupted level-up would be committed in a later session"
    )

if not calls(exit_, "HGLL_ClearPendingPicks"):
    failures.append(
        "hgll_client_exit.nss does not call HGLL_ClearPendingPicks() — a logout mid "
        "level-up would write the staged picks into the .bic"
    )

# 3. the per-skill cap still sees the staged points
avail = re.search(
    r"int\s+GetIsSkillAvailable\s*\([^)]*\)\s*\{(.*?)\n\}", funcs, flags=re.S
)
if not avail:
    failures.append("hgll_func_inc.nss does not define GetIsSkillAvailable()")
else:
    body = avail.group(1)
    if not calls(body, "HGLL_GetPendingSkillPoints"):
        failures.append(
            "GetIsSkillAvailable() does not add HGLL_GetPendingSkillPoints() to the live "
            "rank — the per-skill cap would not bind during the conversation"
        )
    if not calls(body, "GetSkillRank"):
        failures.append(
            "GetIsSkillAvailable() no longer reads GetSkillRank() — the cap must be based "
            "on true invested ranks, not the BASE_* markers (armor-check skills break)"
        )

if failures:
    for f in failures:
        print("  FAIL: %s" % f, file=sys.stderr)
    print("hgll transactional check: %d failure(s)" % len(failures), file=sys.stderr)
    sys.exit(1)

print("hgll transactional check: ok")
