#!/usr/bin/env python3
"""gen-xptable.py — generate hak_2da/xptable.2da, the KILL AWARD table (levels 1-40).

xptable.2da is what the ENGINE pays for a kill below character level 41:

    award = xptable.2da[level][min(CR, last column)] x Mod_XPScale / 10

Mod_XPScale is 150 on this module, so the table is authored in units of XP/15.
Levels 41-60 are not in the table at all — the engine has no rows there and pays
nothing, so that half is paid in script by unpacked/ll_xp_inc.nss. THE TWO HALVES
ARE ONE MODEL and must be retuned together; ll_xp_inc.nss's header carries the
same anchor list this script does.

WHY THIS SCRIPT EXISTS. The table shipped in 37ceff38ff2 with no generator, so the
model lived only in the numbers. That made the low-CR defect below invisible and
unfixable without hand-editing 8,040 cells. The model now lives here, and
tests/check_epic_tables.py re-derives the 2DA from this script rather than
transcribing it a second time.

THE MODEL. Every level has a difficulty TIER — the CR that pays the full 6,000 —
and the award falls off below it:

    r     = CR / tier(L)
    award = PEAK (6000)                                    when r >= 1
            FLOOR (60)                                     when r <= knee(L)
            FLOOR + (PEAK-FLOOR) * f ^ E(L),               otherwise
                                   f = (r - knee) / (1 - knee)

THE DEFECT THIS SCRIPT FIXES (2026-08-13, second pass). The knee was a flat 0.05
of tier at every level. tier(1) is CR 30, so at level 1 the knee sat at CR 1.5 --
it swallowed the starter content itself. Measured in game: a level 1 character
killed a CR 0.5 Bree graveyard skeleton for the 60 floor, the same as a level 55
did, and the level-1 row jumped 12x between CR 1 (60) and CR 2 (746). The knee now
fades in: near zero at level 1, reaching the shipped 0.05 at level 21. Admin
decision: a level 1 / CR 0.5 kill pays ~300, and levels 21+ do not move.

The 60 floor at HIGH level is correct and deliberate — at level 55 the tier is
CR 250, so trash pays a token 60. That is "you outgrow content" working.

THE ANCHORS. Four numbers the admin chose directly (2026-08-13), plus the low-CR
one added by the second pass. The first three live here, the fourth in
ll_xp_inc.nss:

    level  1, CR 0.5 ->   300     <- second pass; sets knee(1)
    level  1, CR  5  -> 2,000
    level  1, CR 30  -> 6,000 (full)
    level 21, CR  5  ->   100
    level 41, CR 30  ->   500     (ll_xp_inc.nss)

Nothing below is transcribed: knee(1), E(1), E(21) and tier(21) are all SOLVED
from those anchors at run time. Change an anchor and both halves must be refitted.

USAGE
    python3 bin/gen-xptable.py            # dry run: report the diff, write nothing
    python3 bin/gen-xptable.py --apply    # write hak_2da/xptable.2da
    python3 bin/gen-xptable.py --show 1   # print one level's row as XP

After --apply the table is only live once the hak is rebuilt AND published:
    bin/build-lotr-rules-hak --install && bin/refresh-nwsync && bin/server-restart
A client holding a stale hak silently reads the old awards.
"""
import argparse
import math
import sys
from pathlib import Path

REPO = Path(__file__).resolve().parent.parent
XPTABLE = REPO / "hak_2da" / "xptable.2da"

# Mod_XPScale is 150 in module.ifo.json and the engine applies it as /10, so a
# table cell of 400 pays 6,000. Cells are therefore XP/15.
XP_SCALE = 15

FLOOR_XP = 60                  # the token award for content far under your tier
PEAK_XP = 6000                 # the module-wide hard cap on one kill, pre-boost
MAX_CR_COL = 200               # last CR column; the engine clamps CR to it

# Levels 1-40 only. 41-60 are ll_xp_inc.nss's half of the same model.
MAX_LEVEL = 40

# Tier ladder endpoints. tier(1) and tier(41) are anchors; tier(21) is solved.
TIER_L1 = 30.0
TIER_L41 = 150.0               # == LLXP_TIER_BASE in ll_xp_inc.nss
KNEE_HIGH = 0.05               # the knee from level 21 up (== LLXP_KNEE)
KNEE_FADE_LEVEL = 21           # the level the softened knee finishes fading out at

# The anchors, as (level, CR, XP).
ANCHOR_L1_LOW = (1, 0.5, 300)
ANCHOR_L1_MID = (1, 5.0, 2000)
ANCHOR_L21_MID = (21, 5.0, 100)


def _shape(y):
    """The fraction of the FLOOR..PEAK span an award of `y` XP sits at."""
    return (y - FLOOR_XP) / (PEAK_XP - FLOOR_XP)


def _solve_exponent(r, xp, knee):
    """E such that award(r, knee, E) == xp."""
    f = (r - knee) / (1.0 - knee)
    return math.log(_shape(xp)) / math.log(f)


def solve_low_knee():
    """Solve knee(1) and E(1) from the two level-1 anchors simultaneously.

    Both must hold at once: CR 0.5 -> 300 and CR 5 -> 2,000, at tier 30. Taking
    the ratio of the two log-equations eliminates E, leaving one equation in the
    knee, which is monotone in it — so bisect. (A single exponent cannot serve
    both the level 1 and level 21 anchors once the knee moves, which is why E is
    interpolated per level below rather than being a constant.)
    """
    _, cr_lo, xp_lo = ANCHOR_L1_LOW
    _, cr_mid, xp_mid = ANCHOR_L1_MID
    r_lo, r_mid = cr_lo / TIER_L1, cr_mid / TIER_L1
    want = math.log(_shape(xp_lo)) / math.log(_shape(xp_mid))

    def residual(k):
        f_lo = (r_lo - k) / (1.0 - k)
        f_mid = (r_mid - k) / (1.0 - k)
        return math.log(f_lo) / math.log(f_mid) - want

    lo, hi = 1e-9, r_lo - 1e-9      # the knee must stay below the low anchor's r
    for _ in range(200):
        mid = (lo + hi) / 2.0
        if residual(lo) * residual(mid) <= 0:
            hi = mid
        else:
            lo = mid
    knee = (lo + hi) / 2.0
    return knee, _solve_exponent(r_mid, xp_mid, knee)


def solve_legacy():
    """The levels 21+ half: E(21), and tier(21) from the level 21 anchor.

    E(21) is the exponent the shipped table was fitted with — solved from the
    level 1 / CR 5 anchor under the OLD flat 0.05 knee. tier(21) then follows from
    the level 21 / CR 5 anchor. Keeping both means rows 21-40 do not move.
    """
    e21 = _solve_exponent(ANCHOR_L1_MID[1] / TIER_L1, ANCHOR_L1_MID[2], KNEE_HIGH)
    _, cr, xp = ANCHOR_L21_MID
    f = _shape(xp) ** (1.0 / e21)
    r = KNEE_HIGH + (1.0 - KNEE_HIGH) * f
    return e21, cr / r


KNEE_L1, E_L1 = solve_low_knee()
E_HIGH, TIER_L21 = solve_legacy()

# Geometric in two segments, because the ladder has three anchors, not two: it
# climbs faster to level 21 (30 -> ~99.8) than from there to level 41 (-> 150).
_STEP_LOW = (TIER_L21 / TIER_L1) ** (1.0 / (KNEE_FADE_LEVEL - 1))
_STEP_HIGH = (TIER_L41 / TIER_L21) ** (1.0 / 20.0)


def tier(level):
    """The CR that pays the full award at `level`."""
    if level <= KNEE_FADE_LEVEL:
        return TIER_L1 * _STEP_LOW ** (level - 1)
    return TIER_L21 * _STEP_HIGH ** (level - KNEE_FADE_LEVEL)


def _fade(level, at_one, at_fade):
    """Linear from `at_one` at level 1 to `at_fade` at KNEE_FADE_LEVEL, then flat."""
    if level >= KNEE_FADE_LEVEL:
        return at_fade
    t = (level - 1) / float(KNEE_FADE_LEVEL - 1)
    return at_one + (at_fade - at_one) * t


def knee(level):
    return _fade(level, KNEE_L1, KNEE_HIGH)


def exponent(level):
    return _fade(level, E_L1, E_HIGH)


def award_xp(level, cr):
    """XP for a kill of `cr` by a character of `level`. Truncated to whole XP."""
    r = cr / tier(level)
    if r >= 1.0:
        return PEAK_XP
    k = knee(level)
    if r <= k:
        return FLOOR_XP
    f = (r - k) / (1.0 - k)
    # Truncate, not round — that is what the shipped table did. The epsilon only
    # rescues a value that float error left a hair BELOW a whole number, which is
    # exactly the case for the anchors themselves (level 21 / CR 5 lands on
    # 99.999999… and would truncate to 99, missing its own anchor by 1).
    return int(FLOOR_XP + (PEAK_XP - FLOOR_XP) * f ** exponent(level) + 1e-6)


def column_cr(col):
    """The CR a column is evaluated at.

    C0 is the "below CR 1" bucket — the engine has no fractional column and the
    creatures that land there are CR 0.125-0.5 trash — so it is evaluated at CR
    0.5 rather than CR 0, which would always be the floor.
    """
    return 0.5 if col == 0 else float(col)


def build():
    """Return {level: [xp per CR column]}, monotone and clamped."""
    table = {
        lvl: [award_xp(lvl, column_cr(c)) for c in range(MAX_CR_COL + 1)]
        for lvl in range(1, MAX_LEVEL + 1)
    }
    # A lower-level character must NEVER be paid less for the same kill (stock's
    # bell curve broke this). The fit is monotone in level already; the running
    # minimum makes it structural rather than something a retune can undo.
    for c in range(MAX_CR_COL + 1):
        best = PEAK_XP
        for lvl in range(1, MAX_LEVEL + 1):
            best = min(best, max(FLOOR_XP, min(PEAK_XP, table[lvl][c])))
            table[lvl][c] = best
    return table


def cell(xp):
    """Format one cell: the table is authored in XP/15, at 6 significant digits."""
    return "%g" % float("%.6g" % (xp / float(XP_SCALE)))


def render(table):
    out = ["2DA V2.0", ""]
    header = "".ljust(11) + "Level".ljust(8)
    header += "".join(("C%d" % c).ljust(9) for c in range(MAX_CR_COL + 1))
    out.append(header.rstrip())
    out.append("")
    for lvl in range(1, MAX_LEVEL + 1):
        line = str(lvl - 1).ljust(11) + str(lvl).ljust(8)
        line += "".join(cell(x).ljust(9) for x in table[lvl])
        out.append(line.rstrip())
    # CRLF: what the toolset writes and what every other 2DA in hak_2da/ uses.
    return "\r\n".join(out) + "\r\n"


def main():
    ap = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    ap.add_argument("--apply", action="store_true", help="write hak_2da/xptable.2da")
    ap.add_argument("--show", type=int, metavar="LEVEL",
                    help="print one level's awards in XP and exit")
    args = ap.parse_args()

    print("model: knee(1)=%.6f  E(1)=%.6f  |  knee(21+)=%.2f  E(21+)=%.6f"
          % (KNEE_L1, E_L1, KNEE_HIGH, E_HIGH))
    print("tier ladder: L1=%.1f  L21=%.4f  L40=%.2f  (L41=%.1f in ll_xp_inc.nss)"
          % (tier(1), tier(21), tier(40), TIER_L41))

    table = build()

    if args.show:
        lvl = args.show
        print("\nlevel %d (tier CR %.1f, knee CR %.2f):" % (lvl, tier(lvl),
                                                            tier(lvl) * knee(lvl)))
        for c in [0, 1, 2, 3, 5, 10, 20, 30, 50, 100, 150, 200]:
            print("  CR %-5s %7d XP" % (column_cr(c), table[lvl][c]))
        return 0

    print("\nsample awards (XP):")
    crs = [0, 1, 2, 3, 5, 10, 30]
    print("  level  " + "".join(("CR %s" % column_cr(c)).rjust(9) for c in crs))
    for lvl in (1, 2, 5, 10, 15, 20, 21, 30, 40):
        print("  %5d  " % lvl + "".join(str(table[lvl][c]).rjust(9) for c in crs))

    text = render(table)
    old = XPTABLE.read_text(encoding="latin-1") if XPTABLE.exists() else ""
    if text == old:
        print("\n%s is up to date." % XPTABLE.relative_to(REPO))
        return 0

    changed = sum(
        1 for a, b in zip(text.splitlines(), old.splitlines()) if a != b
    ) if old else MAX_LEVEL
    if not args.apply:
        print("\nDRY RUN: %d line(s) would change in %s. Re-run with --apply."
              % (changed, XPTABLE.relative_to(REPO)))
        return 0

    XPTABLE.write_text(text, encoding="latin-1")
    print("\nwrote %s (%d line(s) changed)." % (XPTABLE.relative_to(REPO), changed))
    print("The hak must be rebuilt and published before clients see it:")
    print("  bin/build-lotr-rules-hak --install && bin/refresh-nwsync"
          " && bin/server-restart")
    return 0


if __name__ == "__main__":
    sys.exit(main())
