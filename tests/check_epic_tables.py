#!/usr/bin/env python3
"""Build gate: the levels 41-60 experience table must stay coherent.

Levels 41-60 are real character levels driven by hak_2da/exptable.2da. Three
things can silently break them, none of which any other check would catch:

1. **A stock re-extraction.** exptable.2da and classes.2da are hand-edited
   copies of game data. Re-extracting either from the NWN install to pick up a
   patch would drop the level 41-60 rows (exptable) or reintroduce the
   multiclass XP penalty (classes) with no visible symptom until a player
   levels.
2. **A retune of the curve in one place only.** The 41-60 values are
   transcribed twice: in exptable.2da, and as the runtime fallback switch in
   unpacked/_build_lvl_inc.nss (the Ping Pong legendary level menu). The
   include's own header says the two must be retuned together. Nothing enforced
   it until this gate.
3. **A shifted sub-40 row.** Rows for levels 1-40 must stay exactly on the
   stock Bioware curve (500 * n * (n - 1)); a stray edit there would move every
   existing character's next-level threshold.

The curve itself: level 41 costs 48,800 XP over level 40's 780,000, and each
step after that is 1.1x the step before it, ending at 3,581,000 for level 60.
Row 60 (level 61) carries the stock 0xFFFFFFFF unreachable-level sentinel, which
is what stops a character at 60.

This gate does NOT check the installed hak — a correct exptable.2da that was
never packed into lotr_rules.hak is still dead in game. Use
`bin/build-lotr-rules-hak` for that; it verifies its own output.

Exit 0 = coherent, 1 = drifted.
"""
import re
import sys
from pathlib import Path

REPO = Path(__file__).resolve().parent.parent
EXPTABLE = REPO / "hak_2da" / "exptable.2da"
CLASSES = REPO / "hak_2da" / "classes.2da"
BUILD_INC = REPO / "unpacked" / "_build_lvl_inc.nss"

LEVEL_40_XP = 780000
FIRST_STEP = 48800          # level 40 -> 41
SENTINEL = "0xFFFFFFFF"
MAX_LEVEL = 60

# The 11 player base classes, by classes.2da Label. Prestige and creature
# "classes" are excluded — the multiclass XP penalty only ever applied to these.
PLAYER_CLASSES = {
    "Barbarian", "Bard", "Cleric", "Druid", "Fighter", "Monk",
    "Paladin", "Ranger", "Rogue", "Sorcerer", "Wizard",
}


def expected_curve():
    """Cumulative XP for every level 1..60, plus the level-61 sentinel."""
    xp = {n: 500 * n * (n - 1) for n in range(1, 41)}   # stock Bioware curve
    step = FIRST_STEP
    total = LEVEL_40_XP
    for n in range(41, MAX_LEVEL + 1):
        total += step
        xp[n] = total
        # It is the per-level *step* that compounds and gets rounded to whole
        # hundreds, not the running total — so the rounding never accumulates.
        # Half rounds up (71,500 -> 78,650 -> 78,700), which is why this is
        # integer arithmetic and not round(), whose banker's rounding would
        # give 78,600 and drift every level after it.
        step = (step * 11 + 500) // 1000 * 100
    return xp


def read_2da(path):
    """Return (header, {row_index: [cells]}) for a 2DA, ignoring blank rows."""
    text = path.read_text(encoding="latin-1")
    lines = [ln.rstrip("\r\n") for ln in text.splitlines()]
    header = lines[2].split() if len(lines) > 2 else []
    rows = {}
    for ln in lines[3:]:
        cells = ln.split()
        if len(cells) < 2 or not cells[0].isdigit():
            continue
        rows[int(cells[0])] = cells
    return header, rows


def check_exptable(problems):
    if not EXPTABLE.exists():
        problems.append(f"{EXPTABLE} is missing — levels 41-60 have no table")
        return {}

    header, rows = read_2da(EXPTABLE)
    try:
        xp_col = header.index("XP") + 1        # +1: cells[0] is the row index
    except ValueError:
        problems.append("exptable.2da has no XP column")
        return {}

    want = expected_curve()
    got = {}
    for level in range(1, MAX_LEVEL + 1):
        row = rows.get(level - 1)              # row index is level - 1
        if row is None:
            problems.append(f"exptable.2da: no row for level {level}")
            continue
        value = row[xp_col]
        if value == SENTINEL:
            problems.append(
                f"exptable.2da: level {level} is the unreachable sentinel — "
                f"the table stops below the level {MAX_LEVEL} cap"
            )
            continue
        got[level] = int(value)
        if got[level] != want[level]:
            band = "stock 1-40 curve" if level <= 40 else "41-60 legendary curve"
            problems.append(
                f"exptable.2da: level {level} is {got[level]}, expected "
                f"{want[level]} ({band})"
            )

    # Above the cap the stock sentinel convention must hold, or characters can
    # keep levelling past 60.
    row61 = rows.get(MAX_LEVEL)
    if row61 is None:
        problems.append(
            f"exptable.2da: no row {MAX_LEVEL} (level {MAX_LEVEL + 1}) — the "
            f"{SENTINEL} sentinel that caps levelling at {MAX_LEVEL} is missing"
        )
    elif row61[xp_col] != SENTINEL:
        problems.append(
            f"exptable.2da: level {MAX_LEVEL + 1} is {row61[xp_col]}, expected "
            f"the {SENTINEL} sentinel"
        )
    return got


def check_fallback(problems, table):
    """The transcribed switch in _build_lvl_inc.nss must match the 2DA."""
    if not BUILD_INC.exists():
        problems.append(f"{BUILD_INC} is missing")
        return
    src = BUILD_INC.read_text(encoding="utf-8")
    cases = {
        int(lvl): int(xp)
        for lvl, xp in re.findall(r"case\s+(\d+):\s*return\s+(\d+);", src)
    }
    for level in range(41, MAX_LEVEL + 1):
        if level not in cases:
            problems.append(
                f"_build_lvl_inc.nss: no fallback case for level {level}"
            )
        elif level in table and cases[level] != table[level]:
            problems.append(
                f"_build_lvl_inc.nss: level {level} fallback is {cases[level]}, "
                f"exptable.2da says {table[level]} — retune both together"
            )


def check_classes(problems):
    """XPPenalty must stay zeroed for the player base classes."""
    if not CLASSES.exists():
        problems.append(f"{CLASSES} is missing")
        return
    header, rows = read_2da(CLASSES)
    try:
        label_col = header.index("Label") + 1
        pen_col = header.index("XPPenalty") + 1
    except ValueError:
        problems.append("classes.2da has no Label/XPPenalty column")
        return
    seen = set()
    for cells in rows.values():
        if pen_col >= len(cells):
            continue
        label = cells[label_col]
        if label not in PLAYER_CLASSES:
            continue
        seen.add(label)
        if cells[pen_col] != "0":
            problems.append(
                f"classes.2da: {label} XPPenalty is {cells[pen_col]}, expected 0 "
                "— a four-class build would take an XP penalty again"
            )
    for missing in sorted(PLAYER_CLASSES - seen):
        problems.append(f"classes.2da: no row for player class {missing}")


def main() -> int:
    problems: list[str] = []
    table = check_exptable(problems)
    check_fallback(problems, table)
    check_classes(problems)

    if problems:
        print("FAIL epic-tables: the levels 41-60 rules data has drifted")
        for p in problems:
            print(f"       {p}")
        print("       these 2DAs are hand-edited copies of game data — see")
        print("       README.md 'Levels 41-60'; rebuild the hak afterwards with")
        print("       bin/build-lotr-rules-hak --install")
        return 1

    print(
        f"ok epic-tables: exptable.2da levels 1-{MAX_LEVEL} on curve "
        f"(41={table.get(41)}, {MAX_LEVEL}={table.get(MAX_LEVEL)}), "
        "fallback switch matches, XPPenalty zeroed"
    )
    return 0


if __name__ == "__main__":
    sys.exit(main())
