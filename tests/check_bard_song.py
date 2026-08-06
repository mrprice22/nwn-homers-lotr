#!/usr/bin/env python3
"""Build gate: the two bard song scripts spend exactly one use each.

Bard Song and Curse Song sit on OPPOSITE sides of one engine rule, and the module
overrides both — which is how they drifted into each other in the first place.

  * Bard Song (unpacked/nw_s2_bardsong.nss) is the FEAT_BARD_SONGS feat itself.
    The engine spends the use when the feat is activated, so stock
    nw_s2_bardsong ends WITHOUT a DecrementRemainingFeatUses. A decrement in
    this script spends a second use.
  * Curse Song (unpacked/x2_s2_cursesong.nss) is its own feat (FEAT_CURSE_SONG)
    that is meant to draw from the bard song pool, so stock x2_s2_cursesong
    decrements FEAT_BARD_SONGS explicitly. Removing that line makes Curse Song
    free.

The module's Bard Song override was written by copying the customized Curse Song
(commit 8c762f5c412) and inherited its decrement — Bard Song cost two uses per
activation while Curse Song correctly cost one, for as long as anyone had been
playing a bard (reported by -Methonash-, roadmap bard-song-consumes-2-uses).

The failure is invisible from the code — both scripts read as correct in
isolation, and the symptom is only "my uses ran out faster than they should" —
so it is checked here rather than left to review.
"""
import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
UNPACKED = ROOT / "unpacked"

# The call, ignoring whitespace, with FEAT_BARD_SONGS as the feat being spent.
DECREMENT = re.compile(
    r"^[^/\n]*\bDecrementRemainingFeatUses\s*\([^)]*FEAT_BARD_SONGS[^)]*\)",
    re.M)

errors = []


def read(path):
    try:
        return path.read_text(encoding="latin-1")
    except OSError as exc:
        errors.append(f"cannot read {path}: {exc}")
        return ""


bardsong = read(UNPACKED / "nw_s2_bardsong.nss")
cursesong = read(UNPACKED / "x2_s2_cursesong.nss")

n = len(DECREMENT.findall(bardsong))
if n:
    errors.append(
        f"nw_s2_bardsong.nss calls DecrementRemainingFeatUses(FEAT_BARD_SONGS) "
        f"{n}x — the engine already spends the use when the Bard Song feat is "
        f"activated, so this spends a SECOND one. Stock nw_s2_bardsong has no "
        f"such call; delete it. (This is the bard-song-consumes-2-uses bug.)")

n = len(DECREMENT.findall(cursesong))
if n != 1:
    errors.append(
        f"x2_s2_cursesong.nss calls DecrementRemainingFeatUses(FEAT_BARD_SONGS) "
        f"{n}x, expected exactly 1 — Curse Song is its own feat and must spend a "
        f"bard song use itself. 0 makes Curse Song free; 2 makes it cost double.")

if errors:
    print("check_bard_song: FAILED", file=sys.stderr)
    for e in errors:
        print(f"  - {e}", file=sys.stderr)
    sys.exit(1)

print("check_bard_song: ok (bard song 0 explicit decrements, curse song 1)")
sys.exit(0)
