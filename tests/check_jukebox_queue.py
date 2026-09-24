#!/usr/bin/env python3
"""Build gate: the player jukebox's queue behaves, and its SQL is really its SQL.

The module has no automated test suite because NWScript cannot be run outside
the game - but the jukebox queue is the one part of this feature that is pure
SQL, so it can be. The ordering rule (a paid tier jumps the queue, first-come
within a tier), the advance, the restart-mid-song recovery and the picker's
filter/sort/page are all exercised here against real SQLite.

Two halves, and the second is what stops this rotting:

  1. Behaviour, against a throwaway in-memory database.
  2. DRIFT. Every statement below is also asserted to appear in
     unpacked/jb_db.nss. A test that quietly stopped testing the shipped query
     would be worse than no test, because it would still say ok.

What this does NOT cover, and what UAT is for: that the engine actually plays
the row, that the timer fires, and that gold leaves the player's purse.
"""
import re
import sqlite3
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
JB_DB = ROOT / "unpacked" / "jb_db.nss"

FAIL = []


def check(label, got, want):
    if got != want:
        FAIL.append("%s: got %r, want %r" % (label, got, want))


# --------------------------------------------------------------- behaviour --

db = sqlite3.connect(":memory:")
c = db.cursor()
c.execute("CREATE TABLE jb_queue ("
          "id INTEGER PRIMARY KEY AUTOINCREMENT,"
          "area TEXT NOT NULL, row INTEGER NOT NULL, dur_sec INTEGER NOT NULL,"
          "tier INTEGER NOT NULL DEFAULT 0, paid INTEGER NOT NULL DEFAULT 0,"
          "uuid TEXT, buyer_name TEXT, queued_at INTEGER NOT NULL,"
          "started_at INTEGER)")
c.execute("CREATE TABLE jb_plays (row INTEGER PRIMARY KEY, name TEXT NOT NULL,"
          " plays INTEGER NOT NULL DEFAULT 0)")

AREA, NOW = "theprancingpo001", 1000

ORDER_QUEUE = "ORDER BY tier DESC, id ASC"
ORDER_PLAYS = "plays DESC, name ASC"
ORDER_NAME = "name ASC"
SQL_RETIRE = ("DELETE FROM jb_queue WHERE area = @a AND started_at IS NOT NULL "
              "AND started_at + dur_sec <= @n")


def enqueue(row, dur, tier, at):
    c.execute("INSERT INTO jb_queue(area,row,dur_sec,tier,paid,uuid,buyer_name,"
              "queued_at,started_at) VALUES(?,?,?,?,0,'u','n',?,NULL)",
              (AREA, row, dur, tier, at))


def head():
    c.execute("SELECT id,row,dur_sec FROM jb_queue WHERE area=? AND "
              "started_at IS NULL " + ORDER_QUEUE + " LIMIT 1", (AREA,))
    return c.fetchone()


def reconcile(now):
    """The three steps of JB_Reconcile, in the order it runs them."""
    c.execute("DELETE FROM jb_queue WHERE area=? AND started_at IS NOT NULL "
              "AND started_at + dur_sec <= ?", (AREA, now))
    c.execute("SELECT row, started_at + dur_sec - ? FROM jb_queue WHERE area=? "
              "AND started_at IS NOT NULL ORDER BY started_at DESC LIMIT 1",
              (now, AREA))
    cur = c.fetchone()
    if cur:
        return ("still-playing", cur[0], cur[1])
    nxt = head()
    if not nxt:
        return ("stop", None, None)
    c.execute("UPDATE jb_queue SET started_at=? WHERE id=?", (now, nxt[0]))
    c.execute("UPDATE jb_plays SET plays = plays + 1 WHERE row = ?", (nxt[1],))
    return ("started", nxt[1], nxt[2])


enqueue(10, 60, 0, NOW)
enqueue(11, 60, 0, NOW + 1)
enqueue(12, 60, 0, NOW + 2)
check("empty room starts the first ordinary song", reconcile(NOW)[1], 10)
enqueue(99, 30, 3, NOW + 5)
check("a higher tier is next though queued last", head()[1], 99)
enqueue(98, 30, 3, NOW + 6)
check("same tier is first-come", head()[1], 99)
enqueue(97, 30, 4, NOW + 7)
check("the top tier outranks the one below", head()[1], 97)

check("mid-song nothing is promoted", reconcile(NOW + 30)[0], "still-playing")
check("mid-song reports the time left", reconcile(NOW + 30)[2], 30)
check("the top tier is promoted at the end", reconcile(NOW + 60)[1], 97)
check("then the tier-3s in queue order (1)", reconcile(NOW + 90)[1], 99)
check("then the tier-3s in queue order (2)", reconcile(NOW + 120)[1], 98)
check("then the ordinary ones resume (1)", reconcile(NOW + 150)[1], 11)
check("then the ordinary ones resume (2)", reconcile(NOW + 210)[1], 12)
check("an empty queue stops, never loops", reconcile(NOW + 270)[0], "stop")
check("nothing is left behind",
      c.execute("SELECT COUNT(*) FROM jb_queue").fetchone()[0], 0)

# A restart loses the engine's music state but not the paid row.
enqueue(20, 300, 0, NOW)
reconcile(NOW)
r = reconcile(NOW + 100)
check("a song still running is re-asserted", r[0], "still-playing")
check("...with the time left, to re-arm the timer", r[2], 200)
check("one that finished while down is retired", reconcile(NOW + 400)[0], "stop")

c.execute("DELETE FROM jb_plays")
for row, name, plays in [(1, "Aribeth Theme 1", 0), (2, "City Night", 7),
                         (3, "Rural Day 1", 3), (4, "City Docks Day", 7),
                         (5, "Tavern Song", 1)]:
    c.execute("INSERT INTO jb_plays VALUES(?,?,?)", (row, name, plays))


def listrows(q, sort, limit, offset):
    order = ORDER_PLAYS if sort == "plays" else ORDER_NAME
    return [r[0] for r in c.execute(
        "SELECT row FROM jb_plays WHERE name LIKE ? ORDER BY " + order
        + " LIMIT ? OFFSET ?", ("%" + q + "%", limit, offset))]


check("A-Z orders by name", listrows("", "", 10, 0), [1, 4, 2, 3, 5])
check("most played, ties by name", listrows("", "plays", 10, 0), [4, 2, 3, 5, 1])
check("the filter is a substring", listrows("city", "", 10, 0), [4, 2])
check("filter and sort compose", listrows("city", "plays", 10, 0), [4, 2])
check("paging walks the same order", listrows("", "", 2, 2), [2, 3])

c.execute("INSERT OR IGNORE INTO jb_plays(row,name,plays) VALUES(2,'City Night',0)")
check("a re-seed keeps an existing play count",
      c.execute("SELECT plays FROM jb_plays WHERE row=2").fetchone()[0], 7)

# -------------------------------------------------------------------- drift --

if not JB_DB.exists():
    FAIL.append("unpacked/jb_db.nss is missing")
else:
    src = JB_DB.read_text(encoding="utf-8")
    src_flat = re.sub(r'"\s*\+\s*"', "", src)   # join NWScript string concatenation
    for label, needle in [
        ("queue ordering", ORDER_QUEUE),
        ("most-played ordering", ORDER_PLAYS),
        ("A-Z ordering", ORDER_NAME),
        ("retire-finished statement", SQL_RETIRE),
        ("play-count increment",
         "UPDATE jb_plays SET plays = plays + 1 WHERE row = @r"),
        ("non-destructive seed", "INSERT OR IGNORE INTO jb_plays"),
    ]:
        if needle not in src_flat:
            FAIL.append("jb_db.nss no longer contains the %s this gate tests "
                        "(%r)" % (label, needle))


# ------------------------------------------------------- the listening buff --
#
# The bug this section exists to prevent: credit used to decay from the moment
# it was granted, while the player was still sitting in the tavern listening.
# With FULL_SEC == DUR_SEC a credit of c seconds buys a window of exactly c
# seconds, so listening a further t seconds decayed by t and added t - NET ZERO.
# The cap was unreachable no matter how long anyone listened. The fix is that
# accrual touches the raw stored credit and nothing expires until the player
# leaves the area, so that is what is asserted here.

CAP, FULL, DUR, STEP = 2, 600, 600, 60


def magnitude(credited):
    steps = min(credited // STEP, FULL // STEP)
    return (CAP * steps) // (FULL // STEP)


def duration(credited):
    steps = min(credited // STEP, FULL // STEP)
    return (DUR * steps) // (FULL // STEP)


# Accrual: four 150-second songs while standing still must reach the cap.
credited = 0
for _ in range(4):
    credited = min(credited + 150, FULL)
check("accrual must not decay while listening", credited, FULL)
check("...and that is the full-size bonus", magnitude(credited), CAP)
check("...for the full duration", duration(credited), DUR)

# The old broken model, kept as a regression witness: decay-then-add pinned the
# credit at one song's length forever.
broken = 0
for _ in range(4):
    live = max(0, broken - 150)          # decayed by the time the next song ends
    broken = min(live + 150, FULL)
check("the old decay-while-listening model was indeed stuck", broken, 150)
check("...which could never reach the cap", magnitude(broken) < CAP, True)

# Partial listening scales both halves, in 1-minute steps.
check("one minute earns a tenth of the window", duration(60), 60)
check("five minutes earns half the window", duration(300), 300)
check("five minutes earns half the size", magnitude(300), CAP // 2)
check("under a minute earns nothing", magnitude(59), 0)
check("over the cap does not overflow", magnitude(FULL * 3), CAP)
check("over the cap does not extend the window", duration(FULL * 3), DUR)

# Leaving is what starts the clock.
NOW = 5000
expires = NOW + duration(FULL)
check("the buff expires a full window after leaving", expires - NOW, DUR)
check("half way through, it is still live", expires - (NOW + DUR // 2) > 0, True)
check("after the window, it is not", expires - (NOW + DUR + 1) > 0, False)

# --------------------------------------------------------- buff-side drift --

BUFF = ROOT / "unpacked" / "jb_buff_inc.nss"
EXIT_SCRIPTS = ["cleanup.nss", "d_purge.nss"]

if not BUFF.exists():
    FAIL.append("unpacked/jb_buff_inc.nss is missing")
else:
    b = BUFF.read_text(encoding="utf-8")
    for label, needle in [
        ("the tuning constants", "JB_BUFF_CAP      = %d" % CAP),
        ("the full-listen constant", "JB_BUFF_FULL_SEC = %d" % FULL),
        ("the duration constant", "JB_BUFF_DUR_SEC  = %d" % DUR),
        ("the step constant", "JB_BUFF_STEP_SEC = %d" % STEP),
        # The fix itself: accrual reads the raw credit, not a decayed one.
        ("raw-credit accrual", "JB_Credited(oPC) + nSeconds"),
        ("payout on leaving", "void JB_GrantOnLeave(object oPC)"),
        ("the exit hook", "void JB_OnLeaveArea(object oPC, object oArea)"),
    ]:
        if needle not in b:
            FAIL.append("jb_buff_inc.nss no longer contains %s (%r)"
                        % (label, needle))

    # The guard local is spelled literally in the shared exit scripts, which do
    # not include jb_buff_inc - so the two spellings must be checked to agree.
    if 'JB_LISTENING = "jb_listening"' not in b:
        FAIL.append("jb_buff_inc.nss no longer defines JB_LISTENING as "
                    '"jb_listening"')
    for name in EXIT_SCRIPTS:
        f = ROOT / "unpacked" / name
        if not f.exists():
            FAIL.append("unpacked/%s is missing" % name)
            continue
        t = f.read_text(encoding="utf-8")
        if '"jb_listening"' not in t or "jb_area_exit" not in t:
            FAIL.append("%s no longer hands off to jb_area_exit on the "
                        '"jb_listening" guard - the buff would never pay out '
                        "in the areas it owns" % name)


if FAIL:
    print("check_jukebox_queue: FAILED")
    for f in FAIL:
        print("  - %s" % f)
    sys.exit(1)

print("check_jukebox_queue: ok (queue ordering, advance, restart recovery, "
      "listing, listening-buff arithmetic; SQL and constants match source)")
