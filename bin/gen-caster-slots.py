#!/usr/bin/env python3
"""gen-caster-slots.py — extend the caster spell tables across levels 41-60.

Levels 41-60 are real character levels, but the stock class spell tables are
**flat from level 20**: cls_spgn_wiz reads `4` at levels 20, 40 and 60 alike. So
a caster crossing 40 gained caster level, DC, duration and damage-cap scaling but
not one extra spell slot for twenty levels. That is what players reported
(roadmap `legendary-caster-spells-on-level-up`).

The NWNX MaxLevel readme names this exact fix: "Spell counts gained can be
configured for the additional levels ... Edit the class spell gain 2da files.
These are cls_spgn_???.2da". hak_2da/classes.2da already points SpellGainTable at
the stock table names, so a same-named 2DA inside lotr_rules.hak overrides it with
no classes.2da change.

This script owns rows 40-59 (levels 41-60) of those tables and nothing else.
Rows 0-39 are left exactly as extracted from the game data, which is what makes
the sub-40 band provably unchanged for every existing character.

    +1 slot at every castable spell level, at each cadence threshold.

    full cadence (wiz/sorc/cler/dru/bard)  44, 48, 52, 56, 60   -> +5 by level 60
    half cadence (pal/rang)                50, 60               -> +2 by level 60

Paladin and ranger are deliberately gentler: levels 41-60 are already mostly a
martial payoff for them.

The spells-KNOWN tables (cls_spkn_sorc/bard) are generated on the full cadence too
but are **not packed into the hak** — see the KNOWN_TABLES note below and README.md
"Levels 41-60". They exist for the diagnostic that decides whether the native
level-up spell picker can be made to work past 40 at all.

Usage:
    python3 bin/gen-caster-slots.py            # dry run: report what would change
    python3 bin/gen-caster-slots.py --apply    # write the tables

Idempotent: a second --apply run reports no changes. tests/check_epic_tables.py
imports the rule table below and fails the build if the tables drift from it — so
retune HERE, never by hand-editing a 2DA, and never by re-extracting from the game
data (that silently reverts rows 40-59 with no in-game symptom until someone
rests).
"""
import argparse
import sys
from pathlib import Path

REPO = Path(__file__).resolve().parent.parent
HAK_2DA = REPO / "hak_2da"

FIRST_LEGENDARY = 41            # first level this script owns
MAX_LEVEL = 60                  # exptable.2da's last real row

FULL_CADENCE = (44, 48, 52, 56, 60)
HALF_CADENCE = (50, 60)

# Spell slots per day. These ARE packed into lotr_rules.hak.
SLOT_TABLES = {
    "cls_spgn_wiz":  FULL_CADENCE,
    "cls_spgn_sorc": FULL_CADENCE,
    "cls_spgn_cler": FULL_CADENCE,
    "cls_spgn_dru":  FULL_CADENCE,
    "cls_spgn_bard": FULL_CADENCE,
    "cls_spgn_pal":  HALF_CADENCE,
    "cls_spgn_rang": HALF_CADENCE,
}

# Spells KNOWN (sorcerer/bard only; every other caster knows its whole list).
# Generated but NOT in bin/build-lotr-rules-hak's RULES_2DA: MaxLevel's readme
# says "there's currently no client interface for PCs to change their known
# spells past level 40", and a table promising a pick the client cannot offer is
# worse than a flat one. Kept generated so the experiment is one line away.
KNOWN_TABLES = {
    "cls_spkn_sorc": FULL_CADENCE,
    "cls_spkn_bard": FULL_CADENCE,
}

TABLES = {**SLOT_TABLES, **KNOWN_TABLES}

BLANK = "****"                  # a spell level the class cannot cast, ever


def bonus(cadence, level):
    """Extra slots at `level` over the level-40 baseline."""
    return sum(1 for threshold in cadence if threshold <= level)


def column_starts(header):
    """Character offsets where each named column begins on a 2DA line.

    2DA is whitespace-delimited, so alignment is cosmetic to the engine -- but
    these files are read in git diffs, so the fixed-width layout is preserved by
    slicing each row at the same offsets the header uses.
    """
    starts, in_token = [], False
    for i, ch in enumerate(header):
        if ch == " ":
            in_token = False
        elif not in_token:
            starts.append(i)
            in_token = True
    return starts


def read_table(path):
    """Return (raw_lines, header_index, {row_index: line_index})."""
    # read_bytes, not read_text: these 2DAs are CRLF, and read_text's universal
    # newline translation would rewrite every line ending in the file -- turning a
    # 170-cell diff into a whole-file diff and dropping the CRs the stock game
    # data ships with. latin-1 because 2DAs are not UTF-8.
    lines = path.read_bytes().decode("latin-1").split("\n")
    header_index = 2
    rows = {}
    for i, line in enumerate(lines[header_index + 1:], start=header_index + 1):
        cells = line.split()
        if cells and cells[0].isdigit():
            rows[int(cells[0])] = i
    return lines, header_index, rows


def rewrite(path, cadence):
    """Rewrite rows 40-59 of one table. Returns (new_text, [change strings])."""
    lines, header_index, rows = read_table(path)
    header = lines[header_index]
    names = header.split()
    starts = column_starts(header)

    # cells[0] is the row index, which sits in the header's leading whitespace and
    # has no header token -- so names[i] / starts[i] is cells[i + 1]. Columns are
    # tracked in cells-space (`col`) and converted to an offset with col - 1.
    spell_cols = [
        (i + 1, name) for i, name in enumerate(names)
        if name.startswith("SpellLevel")
    ]
    if not spell_cols:
        raise SystemExit(f"{path.name}: no SpellLevel* columns")

    baseline_index = rows.get(39)       # level 40
    if baseline_index is None:
        raise SystemExit(f"{path.name}: no row 39 (level 40) to build on")
    baseline = lines[baseline_index].split()

    changes = []
    for level in range(FIRST_LEGENDARY, MAX_LEVEL + 1):
        row = level - 1
        line_index = rows.get(row)
        if line_index is None:
            raise SystemExit(f"{path.name}: no row {row} (level {level})")

        line = lines[line_index].rstrip("\r")
        had_cr = lines[line_index].endswith("\r")
        width = len(line)
        chars = list(line)

        for col, name in spell_cols:
            base = baseline[col]
            # A class that cannot cast this spell level at 40 never can -- a
            # number here would invent cantrips for paladins and rangers.
            want = base if base == BLANK else str(int(base) + bonus(cadence, level))
            start = starts[col - 1]
            end = starts[col] if col < len(starts) else width
            field = want.ljust(end - start)
            if "".join(chars[start:end]) != field:
                changes.append(f"  level {level} {name}: "
                               f"{''.join(chars[start:end]).strip()} -> {want}")
            chars[start:end] = field

        rebuilt = "".join(chars)[:width].ljust(width)
        lines[line_index] = rebuilt + ("\r" if had_cr else "")

    return "\n".join(lines), changes


def main():
    ap = argparse.ArgumentParser(description=__doc__.split("\n")[0])
    ap.add_argument("--apply", action="store_true",
                    help="write the tables (default is a dry run)")
    args = ap.parse_args()

    missing = [n for n in TABLES if not (HAK_2DA / f"{n}.2da").exists()]
    if missing:
        print(f"error: missing tables in {HAK_2DA}: {', '.join(sorted(missing))}",
              file=sys.stderr)
        print("       seed them from the game data first -- see the 'Levels 41-60'",
              file=sys.stderr)
        print("       section of README.md for the nwn_resman_cat recipe.",
              file=sys.stderr)
        return 1

    total = 0
    for name, cadence in TABLES.items():
        path = HAK_2DA / f"{name}.2da"
        text, changes = rewrite(path, cadence)
        tag = "" if name in SLOT_TABLES else "  (not packed -- experimental)"
        if changes:
            total += len(changes)
            print(f"{name}.2da: {len(changes)} cell(s){tag}")
            for c in changes[:6]:
                print(c)
            if len(changes) > 6:
                print(f"  ... and {len(changes) - 6} more")
            if args.apply:
                path.write_bytes(text.encode("latin-1"))
        else:
            print(f"{name}.2da: already current{tag}")

    if not total:
        print("\nnothing to do -- all tables match the cadence")
    elif args.apply:
        print(f"\napplied {total} cell(s). Next:")
        print("  python3 tests/check_epic_tables.py")
        print("  bin/build-lotr-rules-hak --install && bin/refresh-nwsync")
    else:
        print(f"\ndry run -- {total} cell(s) would change. Re-run with --apply.")
    return 0


if __name__ == "__main__":
    sys.exit(main())
