#!/usr/bin/env python3
"""Build gate: the levels 41-60 rules data must stay coherent.

Levels 41-60 are real character levels driven by hak_2da/exptable.2da. Four
things can silently break them, none of which any other check would catch:

1. **A stock re-extraction.** exptable.2da and classes.2da are hand-edited
   copies of game data. Re-extracting either from the NWN install to pick up a
   patch would drop the level 41-60 rows (exptable) or reintroduce the
   multiclass XP penalty (classes) with no visible symptom until a player
   levels.
2. **A retune of the curve in one place only.** The 41-60 values are
   transcribed three times: in exptable.2da, as the runtime fallback switch in
   unpacked/_build_lvl_inc.nss (the Ping Pong legendary level menu), and as
   XP_LEVEL_60 in unpacked/code_redeem.nss (the freelegendary promo code, which
   SetXP's a character to exactly that total). The include's own header says
   they must be retuned together. Nothing enforced it until this gate.
3. **A shifted sub-40 row.** Rows for levels 1-40 must stay exactly on the
   stock Bioware curve (500 * n * (n - 1)); a stray edit there would move every
   existing character's next-level threshold.
4. **Half the level cap.** server.env carries two independent caps — the NWNX
   plugin's (which lets a character gain the level) and the server's own -maxlevel
   (which decides whether it may log back in). Raising only the first levels a
   character past 40 and then locks it out of the server that levelled it. That
   is not hypothetical; it happened on 2026-07-27 during UAT.
5. **Flat caster tables.** The seven hak_2da/cls_spgn_*.2da tables carry the
   spell slots per day that levels 41-60 grant. Stock is flat from level 20, so a
   re-extraction (or a hand edit) silently reverts twenty levels of caster
   progression with no symptom until a player rests and counts slots. Rows 40-59
   are owned by bin/gen-caster-slots.py; this gate re-derives them from that
   script's own cadence table rather than transcribing the numbers a second time.

The curve itself: level 41 costs 48,800 XP over level 40's 780,000, and each
step after that is 1.1x the step before it, ending at 3,581,000 for level 60.
Row 60 (level 61) carries the stock 0xFFFFFFFF unreachable-level sentinel, which
is what stops a character at 60.

This gate does NOT check the installed hak — a correct exptable.2da that was
never packed into lotr_rules.hak is still dead in game. Use
`bin/build-lotr-rules-hak` for that; it verifies its own output.

Exit 0 = coherent, 1 = drifted.
"""
import importlib.util
import re
import sys
from pathlib import Path

REPO = Path(__file__).resolve().parent.parent
EXPTABLE = REPO / "hak_2da" / "exptable.2da"
CLASSES = REPO / "hak_2da" / "classes.2da"
BUILD_INC = REPO / "unpacked" / "_build_lvl_inc.nss"
CODE_REDEEM = REPO / "unpacked" / "code_redeem.nss"
XPTABLE = REPO / "hak_2da" / "xptable.2da"
# 6,000 XP hard cap / Mod_XPScale of 150 applied as /10 (x15). If Mod_XPScale
# ever changes, this and ll_xp_inc.nss's XP_KILL_CAP must move together.
XPTABLE_CAP_RAW = 400

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


def check_code_redeem(problems, table):
    """code_redeem.nss's XP_LEVEL_60 is the third copy of the same number.

    The `freelegendary` promo code tops a character up to exactly level 60 with
    an absolute SetXP, so a stale constant here would set players to the wrong
    level rather than merely display something odd.
    """
    if not CODE_REDEEM.exists():
        return                      # optional consumer; nothing to reconcile
    src = CODE_REDEEM.read_text(encoding="utf-8")
    m = re.search(r"const\s+int\s+XP_LEVEL_60\s*=\s*(\d+)\s*;", src)
    if not m:
        problems.append("code_redeem.nss: XP_LEVEL_60 constant not found")
        return
    want = table.get(MAX_LEVEL)
    if want is not None and int(m.group(1)) != want:
        problems.append(
            f"code_redeem.nss: XP_LEVEL_60 is {m.group(1)}, exptable.2da says "
            f"{want} — the freelegendary code would set the wrong level"
        )


def check_xptable(problems):
    """xptable.2da is the kill-AWARD table, and it is hand-corrected.

    Two properties, both of which a stock re-extraction would silently undo:

    1. Every cell <= XPTABLE_CAP_RAW. Stock peaks at 600, which is 9,000 XP at
       Mod_XPScale 150 -- above the admin's 6,000 hard cap on a single kill.
    2. Each CR column is non-increasing with level. Stock rises and then falls
       (a bell curve), so a level 1 character was paid LESS than a level 6 for
       the identical kill. A lower-level player must never be paid less.
    """
    if not XPTABLE.exists():
        problems.append(f"{XPTABLE} is missing -- kill awards revert to stock")
        return
    header, rows = read_2da(XPTABLE)
    if not rows:
        problems.append("xptable.2da: no data rows")
        return

    # cells[0] is the row index and cells[1] the Level label, so the CR columns
    # C0..C40 start at cells[2]. Comparing from cells[1] instead compares the
    # Level column with itself and reports 39 phantom failures.
    FIRST_CR = 2
    rowidx = sorted(rows)
    ncol = min(len(rows[r]) for r in rowidx)
    over = []
    for r in rowidx:
        for c in range(FIRST_CR, ncol):
            try:
                v = float(rows[r][c])
            except ValueError:
                continue
            if v > XPTABLE_CAP_RAW:
                over.append(f"level {r + 1} CR {c - FIRST_CR} = {v:g}")
    if over:
        problems.append(
            f"xptable.2da: {len(over)} cell(s) above the {XPTABLE_CAP_RAW} cap "
            f"({XPTABLE_CAP_RAW * 15:,} XP) -- e.g. {', '.join(over[:3])}"
        )

    # Every level must have SOME creature that pays the full award. The engine
    # clamps a creature's CR to the last column, so once the level's difficulty
    # tier climbs past that column nothing in the game can pay full again --
    # silently, with no error. Stock stops at C40; this copy runs to C200 because
    # the tier ladder reaches 147 by level 40. Caught exactly this on 2026-08-13,
    # where 6,000 was reachable only at levels 1-5.
    starved = [
        r + 1 for r in rowidx
        if max((float(v) for v in rows[r][FIRST_CR:ncol]
                if v.replace(".", "", 1).replace("-", "", 1).isdigit()),
               default=0.0) < XPTABLE_CAP_RAW - 1e-9
    ]
    if starved:
        problems.append(
            f"xptable.2da: {len(starved)} level(s) cannot reach the "
            f"{XPTABLE_CAP_RAW * 15:,} XP cap at ANY CR -- the last CR column is "
            f"below the level's difficulty tier (levels {starved[:5]})"
        )

    rising = []
    for c in range(FIRST_CR, ncol):
        for a, b in zip(rowidx, rowidx[1:]):
            try:
                va, vb = float(rows[a][c]), float(rows[b][c])
            except ValueError:
                continue
            if vb > va + 1e-9:
                rising.append(
                    f"CR {c - FIRST_CR}: level {a + 1} pays {va:g} "
                    f"but level {b + 1} pays {vb:g}"
                )
    if rising:
        problems.append(
            f"xptable.2da: {len(rising)} case(s) where a HIGHER level is paid more "
            f"for the same CR -- e.g. {rising[0]}"
        )

    check_xptable_model(problems, rows)


def load_xptable_model():
    """Import bin/gen-xptable.py, which owns the levels 1-40 award model.

    Same reasoning as load_caster_rules(): the table shipped once with no
    generator and the model existed only as 8,040 numbers, which is how the
    low-CR defect below went unnoticed. Import it; never transcribe it.
    """
    path = REPO / "bin" / "gen-xptable.py"
    if not path.exists():
        return None
    spec = importlib.util.spec_from_file_location("gen_xptable", path)
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


def check_xptable_model(problems, rows):
    """The 2DA must be exactly what bin/gen-xptable.py generates, and its low-CR
    end must still pay a starting character properly.

    THE LOW-CR CHECK is the regression this exists to catch. The award falls off
    below the level's difficulty tier and floors at 60 -- correct at high level
    ("you outgrow content"), but the knee was a flat 5% of tier at EVERY level, so
    at level 1 it sat at CR 1.5 and swallowed the starter content itself. A level 1
    character killed a CR 0.5 skeleton for the same 60 a level 55 got, and the
    level-1 row jumped 12x between CR 1 (60) and CR 2 (746). A future retune that
    reintroduces a flat knee would silently do it again.
    """
    gen = load_xptable_model()
    if gen is None:
        problems.append(
            "bin/gen-xptable.py is missing -- nothing owns the levels 1-40 kill "
            "award model, and xptable.2da becomes 8,040 unexplained numbers"
        )
        return

    want = gen.build()
    drift = []
    for level, awards in want.items():
        row = rows.get(level - 1)
        if row is None:
            problems.append(f"xptable.2da: no row for level {level}")
            continue
        for col, xp in enumerate(awards):
            cell = gen.cell(xp)
            if col + 2 >= len(row):
                drift.append(f"level {level} has no C{col}")
            elif row[col + 2] != cell:
                drift.append(
                    f"level {level} C{col} is {row[col + 2]}, generator says {cell}"
                )
    if drift:
        problems.append(
            f"xptable.2da: {len(drift)} cell(s) differ from bin/gen-xptable.py -- "
            f"re-run it with --apply instead of hand-editing "
            f"(e.g. {drift[0]})"
        )

    # C0 is the "below CR 1" bucket, where the starter content lives.
    starter = want[1][0]
    if starter < 250:
        problems.append(
            f"xptable.2da: a level 1 character is paid {starter} XP for the "
            f"lowest-CR kill in the game -- the knee has swallowed the starter "
            f"content again (expected ~300; see bin/gen-xptable.py)"
        )

    # No cliff on the level 1 row: adjacent CR columns must not jump more than 3x
    # while the award is still climbing. 60 -> 746 between CR 1 and CR 2 was the
    # symptom players actually hit.
    row1 = want[1]
    for col in range(len(row1) - 1):
        lo, hi = row1[col], row1[col + 1]
        if hi >= gen.PEAK_XP:
            break
        if hi > lo * 3:
            problems.append(
                f"xptable.2da: level 1 jumps {lo} -> {hi} XP between CR "
                f"{gen.column_cr(col):g} and CR {gen.column_cr(col + 1):g} -- a "
                f"low-CR cliff on the row every new character plays"
            )
            break


def check_level_cap(problems, table):
    """server.env's two level caps must agree with each other and the table.

    There are two independent caps and they are easy to confuse:

      NWN_MAXLEVEL       the SERVER's own restriction, passed to nwserver as
                         -maxlevel and written into settings.tml by bin/serve.
                         It is what the server browser advertises and what
                         refuses a login with "character level disallowed by
                         server restrictions".
      NWNX_MAXLEVEL_MAX  the NWNX MaxLevel plugin's cap, which is what lets a
                         character gain the level in the first place.

    Setting only the NWNX one produces the worst possible outcome: the server
    happily levels a character past 40 and then refuses to let it back in --
    locked out of the very server that levelled it. That happened on 2026-07-27.
    """
    env = REPO / "server.env"
    if not env.exists():
        return
    text = env.read_text(encoding="utf-8")

    def value(key):
        m = re.search(rf"(?m)^{key}=(\S+)", text)
        if not m:
            return None
        return m.group(1).strip().strip('"').strip("'")

    skip = value("NWNX_MAXLEVEL_SKIP")
    if skip != "n":
        return                      # plugin off: levels past 40 aren't enabled

    server_cap = value("NWN_MAXLEVEL")
    plugin_cap = value("NWNX_MAXLEVEL_MAX")

    if server_cap is None:
        problems.append(
            "server.env: NWNX_MAXLEVEL_SKIP=n but no NWN_MAXLEVEL — the server "
            "would default to -maxlevel 40 and refuse a level 41+ character at "
            "login after letting it level"
        )
        return

    # The plugin cap may be written as "$NWN_MAXLEVEL"; that is the intended
    # single-source form and needs no numeric comparison.
    if plugin_cap not in ("$NWN_MAXLEVEL", "${NWN_MAXLEVEL}", server_cap):
        problems.append(
            f"server.env: NWN_MAXLEVEL={server_cap} but "
            f"NWNX_MAXLEVEL_MAX={plugin_cap} — the two caps must match, or "
            "characters get locked out above the lower one"
        )

    if server_cap.isdigit() and int(server_cap) != MAX_LEVEL:
        problems.append(
            f"server.env: NWN_MAXLEVEL={server_cap} but exptable.2da tops out "
            f"at level {MAX_LEVEL}"
        )

    if value("NWNX_ELC_SKIP") != "n":
        problems.append(
            "server.env: NWNX_MAXLEVEL_SKIP=n needs NWNX_ELC_SKIP=n — the "
            "MaxLevel plugin requires NWNX_ELC to be loaded to bypass the "
            "engine's level-40 restriction"
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


def load_caster_rules():
    """Import bin/gen-caster-slots.py for its cadence table.

    Imported rather than re-transcribed on purpose: the whole reason this file
    exists is that the 41-60 XP curve was written down three times with nothing
    tying the copies together. Do not repeat that with the caster cadence.
    """
    path = REPO / "bin" / "gen-caster-slots.py"
    if not path.exists():
        return None
    spec = importlib.util.spec_from_file_location("gen_caster_slots", path)
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


def check_caster_slots(problems):
    """hak_2da/cls_spgn_*.2da rows 40-59 must match the generator's cadence."""
    rules = load_caster_rules()
    if rules is None:
        problems.append(
            "bin/gen-caster-slots.py is missing — nothing owns the caster spell "
            "slots for levels 41-60"
        )
        return 0

    checked = 0
    for stem, cadence in rules.SLOT_TABLES.items():
        path = REPO / "hak_2da" / f"{stem}.2da"
        if not path.exists():
            problems.append(
                f"hak_2da/{stem}.2da is missing — casters of that class gain no "
                "spell slots from 41 to 60"
            )
            continue

        header, rows = read_2da(path)
        spell_cols = [
            (i + 1, name) for i, name in enumerate(header)
            if name.startswith("SpellLevel")
        ]
        if not spell_cols:
            problems.append(f"{stem}.2da: no SpellLevel* columns")
            continue

        base = rows.get(39)                 # level 40
        lvl20 = rows.get(19)                 # level 20
        if base is None or lvl20 is None:
            problems.append(f"{stem}.2da: missing row 19 or row 39")
            continue

        # The stock table is flat across the whole epic band. If level 40 no longer
        # equals level 20, someone edited the sub-40 rows this script must not own.
        for col, name in spell_cols:
            if base[col] != lvl20[col]:
                problems.append(
                    f"{stem}.2da: {name} differs between level 20 ({lvl20[col]}) "
                    f"and level 40 ({base[col]}) — the sub-40 band was edited; "
                    "only rows 40-59 belong to bin/gen-caster-slots.py"
                )

        num_col = header.index("NumSpellLevels") + 1 if "NumSpellLevels" in header else None

        for level in range(41, MAX_LEVEL + 1):
            row = rows.get(level - 1)
            if row is None:
                problems.append(f"{stem}.2da: no row for level {level}")
                continue
            for col, name in spell_cols:
                stock = base[col]
                if stock == rules.BLANK:
                    # A class that cannot cast this spell level at 40 never can.
                    want = rules.BLANK
                else:
                    want = str(int(stock) + rules.bonus(cadence, level))
                if row[col] != want:
                    problems.append(
                        f"{stem}.2da: level {level} {name} is {row[col]}, expected "
                        f"{want} (cadence {'/'.join(str(t) for t in cadence)})"
                    )
            if num_col is not None and row[num_col] != base[num_col]:
                problems.append(
                    f"{stem}.2da: level {level} NumSpellLevels is "
                    f"{row[num_col]}, expected {base[num_col]} — 41-60 grants "
                    "more slots, never a new spell level"
                )
        checked += 1
    return checked


def main() -> int:
    problems: list[str] = []
    table = check_exptable(problems)
    check_fallback(problems, table)
    check_code_redeem(problems, table)
    check_xptable(problems)
    check_level_cap(problems, table)
    check_classes(problems)
    casters = check_caster_slots(problems)

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
        "fallback switch + XP_LEVEL_60 match, both level caps at 60, "
        f"XPPenalty zeroed, {casters} caster slot table(s) on cadence"
    )
    return 0


if __name__ == "__main__":
    sys.exit(main())
