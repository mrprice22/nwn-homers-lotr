// jb_db.nss - the player jukebox's queue, play counts and gold tiers.
//
// WHAT IS PERSISTENT AND WHY
//
// The admin jukebox is deliberately not persistent: its state is area locals
// and it dies at reboot (jb_inc.nss). That is right for a free admin toy and
// wrong here, because players PAY. A queue that vanished on restart would take
// their gold with it, so the queue lives in SQLite and survives.
//
// What is NOT persisted is the engine's music state, which cannot be: after a
// restart the room is playing its own music again and nothing knows otherwise.
// JB_Reconcile() handles that by treating a song whose window has not yet
// elapsed as one to (re)start, so a player who paid hears their song even if
// the server went down in the middle of it. It restarts from the beginning
// because MusicBackgroundPlay cannot seek.
//
// TIME IS SETTLED LAZILY, the way boost_db.nss does it - a stored wall-clock
// epoch compared to now, never the game clock (an in-game hour is about two
// real minutes). The one honest exception is that a song has to end even when
// nobody is clicking, so JB_Arm() sets a single DelayCommand at track end,
// guarded by a generation counter so a superseded timer no-ops. That is the
// idiom bonus_pool_inc and fat_inc already use for expiry. A per-area
// OnHeartbeat poll would be the alternative and is not this module's style.
//
// WHY THE TRACK NAMES ARE IN THE DATABASE
//
// jb_plays carries the name as well as the count, seeded from jb_catalog.nss.
// That lets one SQL statement do the filtering, the ordering and the paging the
// picker needs - including "sort by most played", which cannot be done in
// NWScript at all: there is no array to sort 113 entries in.
//
// IDENTITY is GetObjectUUID(), never the engine's derived campaign key. See
// mw_db.nss:1-40 for what that key cost the last time: it is account name plus
// character name truncated, two characters on one account collided, and a
// re-roll claimed a permanent reward seven times.
#include "jb_catalog"
#include "jb_inc"

const string JB_DB = "jukeboxdb";

// Area locals owned by this file (the music-state ones belong to jb_inc).
const string JB_GEN = "JB_GEN";   // generation counter for the armed end-of-track timer

// ---------------------------------------------------------------- gold tiers
//
// Tier 0 is the ordinary price. Tiers 1-4 buy PRIORITY: a higher tier jumps the
// whole queue ahead of every lower one, and ties break first-come. The step is
// steeply exponential, and the top of it is the roadmap item's own ceiling -
// 100 million is meant to be a thing somebody does once, not a way to own the
// room.
const int JB_TIER_MAX = 4;

int JB_TierCost(int nTier)
{
    switch (nTier)
    {
        case 0: return 100;
        case 1: return 5000;
        case 2: return 150000;
        case 3: return 4000000;
        case 4: return 100000000;
    }
    return 100;
}

string JB_TierName(int nTier)
{
    switch (nTier)
    {
        case 0: return "Ordinary";
        case 1: return "Sooner";
        case 2: return "Much sooner";
        case 3: return "Next but one";
        case 4: return "Next, and be quiet about it";
    }
    return "Ordinary";
}

// "1,234,567" - the module's one gold formatter lives in store_appr_inc, which
// this file does not otherwise need, so the grouping is repeated here rather
// than dragging a whole store include into the jukebox.
string JB_Gold(int n)
{
    if (n < 0) return IntToString(n);
    string sOut = "";
    string sIn = IntToString(n);
    int nLen = GetStringLength(sIn);
    int i;
    for (i = 0; i < nLen; i++)
    {
        if (i > 0 && (nLen - i) % 3 == 0) sOut += ",";
        sOut += GetSubString(sIn, i, 1);
    }
    return sOut;
}

// ------------------------------------------------------------------- helpers

int JB_Now()
{
    sqlquery q = SqlPrepareQueryCampaign(JB_DB,
        "SELECT CAST(strftime('%s','now') AS INTEGER)");
    return SqlStep(q) ? SqlGetInt(q, 0) : 0;
}

// The key a queue is filed under. An area's resref is stable across reboots,
// which ObjectToString is not.
string JB_AreaKey(object oArea)
{
    return GetResRef(oArea);
}

// ------------------------------------------------------------------- schema

void JB_InitDb()
{
    sqlquery q = SqlPrepareQueryCampaign(JB_DB,
        "CREATE TABLE IF NOT EXISTS jb_queue (" +
        "id INTEGER PRIMARY KEY AUTOINCREMENT," +
        "area TEXT NOT NULL," +            // area resref
        "row INTEGER NOT NULL," +          // RAW ambientmusic.2da row
        "dur_sec INTEGER NOT NULL," +      // measured length, from the catalogue
        "tier INTEGER NOT NULL DEFAULT 0," +
        "paid INTEGER NOT NULL DEFAULT 0," +
        "uuid TEXT," +                     // GetObjectUUID of the buyer
        "buyer_name TEXT," +
        "queued_at INTEGER NOT NULL," +
        "started_at INTEGER)");            // NULL until it is the one playing
    SqlStep(q);

    sqlquery qi = SqlPrepareQueryCampaign(JB_DB,
        "CREATE INDEX IF NOT EXISTS jb_queue_area ON jb_queue(area, tier DESC, id)");
    SqlStep(qi);

    sqlquery qp = SqlPrepareQueryCampaign(JB_DB,
        "CREATE TABLE IF NOT EXISTS jb_plays (" +
        "row INTEGER PRIMARY KEY," +
        "name TEXT NOT NULL," +
        "plays INTEGER NOT NULL DEFAULT 0)");
    SqlStep(qp);

    // Seed (and re-seed) the names from the generated catalogue. Only done when
    // the counts disagree, so a normal module load does no work: adding a track
    // is the only thing that changes this, and it changes the count.
    sqlquery qc = SqlPrepareQueryCampaign(JB_DB, "SELECT COUNT(*) FROM jb_plays");
    int nHave = SqlStep(qc) ? SqlGetInt(qc, 0) : 0;
    if (nHave == JB_CatCount()) return;

    int i;
    for (i = 0; i < JB_CatCount(); i++)
    {
        // INSERT OR IGNORE, not REPLACE: a replace would reset the play count
        // of every existing track every time a new one was added.
        sqlquery qn = SqlPrepareQueryCampaign(JB_DB,
            "INSERT OR IGNORE INTO jb_plays(row, name, plays) VALUES(@r, @n, 0)");
        SqlBindInt(qn, "@r", JB_CatRow(i));
        SqlBindString(qn, "@n", JB_CatName(i));
        SqlStep(qn);

        // A renamed track still updates its label without touching the count.
        sqlquery qu = SqlPrepareQueryCampaign(JB_DB,
            "UPDATE jb_plays SET name = @n WHERE row = @r");
        SqlBindInt(qu, "@r", JB_CatRow(i));
        SqlBindString(qu, "@n", JB_CatName(i));
        SqlStep(qu);
    }
}

// ------------------------------------------------------------- play counting

void JB_BumpPlays(int nRow)
{
    sqlquery q = SqlPrepareQueryCampaign(JB_DB,
        "UPDATE jb_plays SET plays = plays + 1 WHERE row = @r");
    SqlBindInt(q, "@r", nRow);
    SqlStep(q);
}

int JB_PlaysFor(int nRow)
{
    sqlquery q = SqlPrepareQueryCampaign(JB_DB,
        "SELECT plays FROM jb_plays WHERE row = @r");
    SqlBindInt(q, "@r", nRow);
    return SqlStep(q) ? SqlGetInt(q, 0) : 0;
}

// ------------------------------------------------------------------- listing
//
// One statement does filter, order and page, which is the whole reason the
// names are in the table. sSort is "plays" or "name"; anything else is treated
// as "name" rather than interpolated, because this string reaches SQL.

string JB_OrderBy(string sSort)
{
    if (sSort == "plays") return "plays DESC, name ASC";
    return "name ASC";
}

int JB_ListCount(string sQuery)
{
    sqlquery q = SqlPrepareQueryCampaign(JB_DB,
        "SELECT COUNT(*) FROM jb_plays WHERE name LIKE @q");
    SqlBindString(q, "@q", "%" + sQuery + "%");
    return SqlStep(q) ? SqlGetInt(q, 0) : 0;
}

// The RAW row at position nOffset of the filtered, sorted list, or -1.
int JB_ListRowAt(string sQuery, string sSort, int nOffset)
{
    sqlquery q = SqlPrepareQueryCampaign(JB_DB,
        "SELECT row FROM jb_plays WHERE name LIKE @q ORDER BY "
        + JB_OrderBy(sSort) + " LIMIT 1 OFFSET @o");
    SqlBindString(q, "@q", "%" + sQuery + "%");
    SqlBindInt(q, "@o", nOffset);
    return SqlStep(q) ? SqlGetInt(q, 0) : -1;
}

// --------------------------------------------------------------------- queue

int JB_QueueLength(object oArea)
{
    sqlquery q = SqlPrepareQueryCampaign(JB_DB,
        "SELECT COUNT(*) FROM jb_queue WHERE area = @a AND started_at IS NULL");
    SqlBindString(q, "@a", JB_AreaKey(oArea));
    return SqlStep(q) ? SqlGetInt(q, 0) : 0;
}

// The entry currently playing in this area, as its raw row, or -1.
int JB_PlayingRow(object oArea)
{
    sqlquery q = SqlPrepareQueryCampaign(JB_DB,
        "SELECT row FROM jb_queue WHERE area = @a AND started_at IS NOT NULL "
        + "ORDER BY started_at DESC LIMIT 1");
    SqlBindString(q, "@a", JB_AreaKey(oArea));
    return SqlStep(q) ? SqlGetInt(q, 0) : -1;
}

void JB_Enqueue(object oArea, int nRow, int nDur, int nTier, int nPaid, object oPC)
{
    sqlquery q = SqlPrepareQueryCampaign(JB_DB,
        "INSERT INTO jb_queue(area, row, dur_sec, tier, paid, uuid, buyer_name, "
        + "queued_at, started_at) VALUES(@a, @r, @d, @t, @p, @u, @n, @q, NULL)");
    SqlBindString(q, "@a", JB_AreaKey(oArea));
    SqlBindInt(q, "@r", nRow);
    SqlBindInt(q, "@d", nDur);
    SqlBindInt(q, "@t", nTier);
    SqlBindInt(q, "@p", nPaid);
    SqlBindString(q, "@u", GetObjectUUID(oPC));
    SqlBindString(q, "@n", GetName(oPC));
    SqlBindInt(q, "@q", JB_Now());
    SqlStep(q);
}

// How many are waiting ahead of a given tier - what a player wants to know
// before paying to jump them.
int JB_AheadOf(object oArea, int nTier)
{
    sqlquery q = SqlPrepareQueryCampaign(JB_DB,
        "SELECT COUNT(*) FROM jb_queue WHERE area = @a AND started_at IS NULL "
        + "AND tier > @t");
    SqlBindString(q, "@a", JB_AreaKey(oArea));
    SqlBindInt(q, "@t", nTier);
    return SqlStep(q) ? SqlGetInt(q, 0) : 0;
}

void JB_Reconcile(object oArea);
void JB_OnTrackEnd(object oArea, int nGen);

// Arm the single end-of-track timer. The generation counter is what makes a
// superseded timer harmless: Stop, or any reconcile that promotes a different
// entry, bumps JB_GEN and the old DelayCommand finds a number it does not
// recognise and returns.
//
// Assigned to the AREA, not to the player who clicked: a delayed command dies
// with the object that owns it, and the player may well walk out or log off
// before the song ends. The area does not.
void JB_Arm(object oArea, int nSeconds)
{
    int nGen = GetLocalInt(oArea, JB_GEN) + 1;
    SetLocalInt(oArea, JB_GEN, nGen);
    AssignCommand(oArea, DelayCommand(IntToFloat(nSeconds) + 1.0,
                                      JB_OnTrackEnd(oArea, nGen)));
}

void JB_OnTrackEnd(object oArea, int nGen)
{
    if (GetLocalInt(oArea, JB_GEN) != nGen) return;   // superseded; do nothing
    JB_Reconcile(oArea);
}

// Settle this area's queue against the wall clock: retire a finished song,
// promote the next one, and stop when there is nothing left.
//
// Safe to call at any time and from anywhere - opening the window, queueing,
// the armed timer. It is the only thing that starts or stops the music on the
// player path.
void JB_Reconcile(object oArea)
{
    if (!GetIsObjectValid(oArea)) return;

    int nNow = JB_Now();
    string sArea = JB_AreaKey(oArea);

    // 1. Retire whatever has finished.
    sqlquery qd = SqlPrepareQueryCampaign(JB_DB,
        "DELETE FROM jb_queue WHERE area = @a AND started_at IS NOT NULL "
        + "AND started_at + dur_sec <= @n");
    SqlBindString(qd, "@a", sArea);
    SqlBindInt(qd, "@n", nNow);
    SqlStep(qd);

    // 2. Is something still mid-song? After a restart the engine has forgotten
    //    it, so re-assert it rather than leaving a paid song silent. It restarts
    //    from the beginning: MusicBackgroundPlay cannot seek.
    sqlquery qc = SqlPrepareQueryCampaign(JB_DB,
        "SELECT row, started_at + dur_sec - @n FROM jb_queue WHERE area = @a "
        + "AND started_at IS NOT NULL ORDER BY started_at DESC LIMIT 1");
    SqlBindString(qc, "@a", sArea);
    SqlBindInt(qc, "@n", nNow);
    if (SqlStep(qc))
    {
        int nRow  = SqlGetInt(qc, 0);
        int nLeft = SqlGetInt(qc, 1);
        if (GetLocalInt(oArea, JB_ROW) != nRow)
        {
            JB_StartRow(oArea, nRow);
            JB_Arm(oArea, nLeft);
        }
        return;
    }

    // 3. Nothing playing. Promote the head of the queue: highest tier first,
    //    first-come within a tier.
    sqlquery qn = SqlPrepareQueryCampaign(JB_DB,
        "SELECT id, row, dur_sec FROM jb_queue WHERE area = @a "
        + "AND started_at IS NULL ORDER BY tier DESC, id ASC LIMIT 1");
    SqlBindString(qn, "@a", sArea);
    if (!SqlStep(qn))
    {
        // Empty queue. Give the room its own music back - this is what "does
        // not loop forever" means.
        if (GetLocalInt(oArea, JB_ON))
        {
            SetLocalInt(oArea, JB_GEN, GetLocalInt(oArea, JB_GEN) + 1);
            JB_Stop(oArea);
        }
        return;
    }

    int nId  = SqlGetInt(qn, 0);
    int nRow = SqlGetInt(qn, 1);
    int nDur = SqlGetInt(qn, 2);

    sqlquery qs = SqlPrepareQueryCampaign(JB_DB,
        "UPDATE jb_queue SET started_at = @n WHERE id = @i");
    SqlBindInt(qs, "@n", nNow);
    SqlBindInt(qs, "@i", nId);
    SqlStep(qs);

    JB_StartRow(oArea, nRow);
    JB_BumpPlays(nRow);
    JB_Arm(oArea, nDur);
}

// Clear an area's queue and silence it. The refund question is deliberately not
// answered here: nothing calls this on the player path, and an admin who stops
// a room is doing it on purpose.
void JB_ClearQueue(object oArea)
{
    sqlquery q = SqlPrepareQueryCampaign(JB_DB,
        "DELETE FROM jb_queue WHERE area = @a");
    SqlBindString(q, "@a", JB_AreaKey(oArea));
    SqlStep(q);

    SetLocalInt(oArea, JB_GEN, GetLocalInt(oArea, JB_GEN) + 1);
    JB_Stop(oArea);
}
