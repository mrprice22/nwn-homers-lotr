#!/usr/bin/env python3
"""Build gate: hak_2da/feat.2da must stay the stock table plus our rows.

feat.2da is the one 2DA in lotr_rules.hak that carries content rather than
tuning, and four things can break it silently:

1. **The wrong base table.** The module resolves the **stock** feat.2da — 1116
   rows (0-1115, last PLAYER_TOOL_10), 43 columns. hak_2da/feat.2da used to hold
   a byte-identical copy of the table inside `cep2_add_feats.hak`, **a hak
   Mod_HakList does not load**: 24,771 rows and 44 columns. Shipping that would
   add ~23,000 CEP weapon-of-choice feats to every character's feat list and
   change the column count under every row.
2. **A re-extraction over the generated file.** Pulling a fresh feat.2da out of
   the game data drops every legendary row, and the only symptom is that a
   granted feat stops existing — the character sheet shows a blank entry.
   bin/gen-legendary-feats.py --from-stock is the supported way to swap the base.
3. **A legendary feat reachable from the engine's own level-up page.** The
   picker is the only grant path; a feat the level-up page can also offer is a
   double-grant. ALLCLASSESCANUSE must be 0 on every owned row, and no
   cls_feat_*.2da may list one.
4. **Rows and TLK strings drifting apart.** Each row's NAME and DESCRIPTION are
   strrefs into our custom TLK. This gate re-derives them from
   bin/gen-legendary-feats.py, which derives them from where bin/build-lotr-tlk
   actually places the strings — so a row pointing at the wrong string fails
   here rather than showing the wrong tooltip in game.

It does NOT check the packed hak: a correct feat.2da that was never packed into
lotr_rules.hak is still dead in game (`bin/build-lotr-rules-hak` verifies its own
output), and it does not check that the strings reached the installed TLK —
that is tests/check_lotr_tlk.py's job.

Exit 0 = coherent, 1 = drifted.
"""
import importlib.util
import sys
from pathlib import Path

REPO = Path(__file__).resolve().parent.parent
GENERATOR = REPO / "bin" / "gen-legendary-feats.py"
FEAT_2DA = REPO / "hak_2da" / "feat.2da"
HAK_BUILDER = REPO / "bin" / "build-lotr-rules-hak"
HAK_2DA_DIR = REPO / "hak_2da"


def load_generator():
    if not GENERATOR.exists():
        return None
    spec = importlib.util.spec_from_file_location("gen_legendary_feats", GENERATOR)
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


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


def check_table(problems, gen):
    if not FEAT_2DA.exists():
        problems.append(f"{FEAT_2DA} is missing — nothing to pack into the hak")
        return

    header, rows = read_2da(FEAT_2DA)
    if len(header) != gen.BASE_COLUMNS:
        problems.append(
            f"feat.2da has {len(header)} columns, expected {gen.BASE_COLUMNS} — "
            "this looks like the CEP cep2_add_feats copy (44 columns), which "
            "the module does not load")
        return

    base = sorted(i for i in rows if i < gen.FIRST_ROW)
    if len(base) != gen.BASE_ROWS or (base and base[-1] != gen.BASE_ROWS - 1):
        problems.append(
            f"feat.2da has {len(base)} rows below {gen.FIRST_ROW}, expected "
            f"{gen.BASE_ROWS} (stock 0-1115) — the base table is not stock")

    index = {col: pos for pos, col in enumerate(header)}
    refs = gen.strrefs()
    owned = sorted(i for i in rows if i >= gen.FIRST_ROW)
    expected = [gen.FIRST_ROW + n for n in range(len(gen.FEATS))]
    if owned != expected:
        # Bounded: a stray CEP table puts ~23,000 row numbers in this list.
        shown = owned[:8] + (["..."] if len(owned) > 8 else [])
        problems.append(
            f"feat.2da has {len(owned)} row(s) at or above {gen.FIRST_ROW} "
            f"({shown or '(none)'}), generator defines {len(expected)} "
            f"({expected}) — either the table was re-extracted over the "
            "generated rows, or it is not the stock base. Re-run: "
            "python3 bin/gen-legendary-feats.py --apply "
            "[--from-stock /tmp/feat.2da]")
        return

    for row_index, feat in zip(owned, gen.FEATS):
        cells = rows[row_index][1:]

        def cell(col):
            return cells[index[col]] if col in index and index[col] < len(cells) else None

        if cell("LABEL") != feat.label:
            problems.append(
                f"feat.2da row {row_index} is {cell('LABEL')!r}, generator says "
                f"{feat.label!r} — rows renumbered, which turns every granted "
                "feat into a different feat")
        # The load-bearing column: 0 keeps the feat off every class's level-up
        # selection list, leaving the picker as the only grant path.
        if cell("ALLCLASSESCANUSE") != "0":
            problems.append(
                f"feat.2da row {row_index} ({feat.label}) has ALLCLASSESCANUSE="
                f"{cell('ALLCLASSESCANUSE')}, must be 0 — otherwise the engine's "
                "own level-up page can offer it alongside the picker and the "
                "character gets it twice")
        name_ref, desc_ref = refs[feat.label]
        if cell("FEAT") != str(name_ref) or cell("DESCRIPTION") != str(desc_ref):
            problems.append(
                f"feat.2da row {row_index} ({feat.label}) points at strrefs "
                f"{cell('FEAT')}/{cell('DESCRIPTION')}, the TLK block puts its "
                f"strings at {name_ref}/{desc_ref} — stale table, re-run "
                "python3 bin/gen-legendary-feats.py --apply")


def check_not_selectable(problems, gen):
    """No cls_feat_*.2da may list an owned feat id.

    ALLCLASSESCANUSE=0 means "only classes whose feat table lists it", so a
    stray entry in one of those tables would re-open the level-up page path
    that column exists to close.
    """
    owned = {str(gen.FIRST_ROW + n) for n in range(len(gen.FEATS))}
    for path in sorted(HAK_2DA_DIR.glob("cls_feat_*.2da")):
        _, rows = read_2da(path)
        for row_index, cells in rows.items():
            if len(cells) > 1 and cells[1] in owned:
                problems.append(
                    f"{path.name} row {row_index} lists feat {cells[1]}, which "
                    "is a legendary feat — that puts it back on a class's "
                    "level-up page")


def check_packed(problems):
    """feat.2da must be in the hak builder's content list, or it never ships."""
    if not HAK_BUILDER.exists():
        problems.append(f"{HAK_BUILDER} is missing")
        return
    text = HAK_BUILDER.read_text(encoding="utf-8")
    body = text.split("RULES_2DA=(", 1)
    if len(body) < 2 or "feat.2da" not in body[1].split(")", 1)[0]:
        problems.append(
            "bin/build-lotr-rules-hak's RULES_2DA does not list feat.2da — the "
            "legendary rows would never reach a client")


def main():
    problems = []
    gen = load_generator()
    if gen is None:
        problems.append(
            f"{GENERATOR} is missing — nothing owns the legendary feat rows")
    else:
        check_table(problems, gen)
        check_not_selectable(problems, gen)
    check_packed(problems)

    if problems:
        print("FAIL: legendary feat table has drifted\n", file=sys.stderr)
        for p in problems:
            print(f"  - {p}", file=sys.stderr)
        return 1
    count = len(gen.FEATS) if gen else 0
    print(f"ok: legendary feats coherent ({count} rows from "
          f"{gen.FIRST_ROW}, stock base intact, none selectable at level-up)")
    return 0


if __name__ == "__main__":
    sys.exit(main())
