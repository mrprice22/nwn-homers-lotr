// loot_db.nss - the lootdb campaign DB (Season 3 rolled loot).
//
// Roadmap: loot-overhaul epic, lo-loot-core (Phase 2).  Design:
// docs.manual/Draft/Loot-Overhaul.html.
//
// Phase 2 owns one table, loot_roll_log: balance telemetry for the rolls that
// matter (every Loot Lab roll, and any Epic-or-better roll from anywhere).  It
// is deliberately NOT every roll - a synchronous SQLite commit per chest item
// would be felt as server lag once Phase 3 puts chests on Loot_Roll.
// Phase 6 adds loot_wishlist (a character's picked base items; the row
// base = -1 means "Auto off"); Phase 7 (Fate token lockout) adds its table here.
//
// Loot_InitDb() is the only DDL and is called from onmoduleload.nss, never
// from client enter (CLAUDE.md: DDL off the login frame).  Table names avoid
// the engine-reserved meta / db / migrations.

const string LOOT_DB = "lootdb";

// Rarity at or above which every roll is logged (3 = Epic).
const int LOOT_LOG_MIN_RARITY = 3;

// Idempotent - safe to call on every module load.
void Loot_InitDb()
{
    sqlquery q = SqlPrepareQueryCampaign(LOOT_DB,
        "CREATE TABLE IF NOT EXISTS loot_roll_log (" +
        "id INTEGER PRIMARY KEY AUTOINCREMENT," +
        "ts TEXT DEFAULT CURRENT_TIMESTAMP," +
        "source TEXT, profile TEXT, lvl INTEGER, rarity INTEGER," +
        "base INTEGER, item TEXT, value INTEGER, beneficiary TEXT)");
    SqlStep(q);
    q = SqlPrepareQueryCampaign(LOOT_DB,
        "CREATE TABLE IF NOT EXISTS loot_wishlist (" +
        "uuid TEXT NOT NULL, base INTEGER NOT NULL, PRIMARY KEY (uuid, base))");
    SqlStep(q);
    // Phase 7: the Shard of Fate bonus-roll lockout - one per character per
    // boss per rolling LOOTD_FATE_LOCKOUT seconds (at = unix time of the roll).
    q = SqlPrepareQueryCampaign(LOOT_DB,
        "CREATE TABLE IF NOT EXISTS loot_fate_lockout (" +
        "uuid TEXT NOT NULL, boss TEXT NOT NULL, at INTEGER NOT NULL," +
        "PRIMARY KEY (uuid, boss))");
    SqlStep(q);
}

// Record one roll.  sItem is the rolled name (or the named-pool resref);
// nValue is the engine gold value the budget was checked against (-1 = named).
void Loot_LogRoll(string sSource, string sProfile, int nLvl, int nRarity,
                  int nBase, string sItem, int nValue, object oBeneficiary)
{
    if (sSource != "lab" && sSource != "fate" && nRarity < LOOT_LOG_MIN_RARITY)
        return;
    sqlquery q = SqlPrepareQueryCampaign(LOOT_DB,
        "INSERT INTO loot_roll_log (source, profile, lvl, rarity, base, item, value, beneficiary) " +
        "VALUES (@s, @p, @l, @r, @b, @i, @v, @u)");
    SqlBindString(q, "@s", sSource);
    SqlBindString(q, "@p", sProfile);
    SqlBindInt(q, "@l", nLvl);
    SqlBindInt(q, "@r", nRarity);
    SqlBindInt(q, "@b", nBase);
    SqlBindString(q, "@i", sItem);
    SqlBindInt(q, "@v", nValue);
    SqlBindString(q, "@u", GetIsObjectValid(oBeneficiary) ? GetObjectUUID(oBeneficiary) : "");
    SqlStep(q);
}

// ---------------------------------------------------------------------------
// Phase 6: the loot wishlist (lo-wishlist)
// ---------------------------------------------------------------------------
// Keyed by GetObjectUUID (per character, like the bestiary). Rolls never read
// the DB per item: the list is cached on the PC as LOOT_WISH = "|1|13|" (plus
// "|-1|" when Auto is off), loaded once by Loot_WishGet and rewritten by every
// change below in the same call. Known gap: the prod -> dev vault sync copies
// the .bic but not lootdb, so wishlists reset on the dev realm.

const string LOOT_WISH    = "LOOT_WISH";     // PC local: cached list
const string LOOT_WISH_OK = "LOOT_WISH_OK";  // PC local: cache loaded
const int    LOOT_WISH_AUTO_OFF = -1;        // sentinel row: Auto switched off

// Read the character's rows from lootdb into the PC cache and return it.
string Loot_WishLoad(object oPC)
{
    string sList = "|";
    sqlquery q = SqlPrepareQueryCampaign(LOOT_DB,
        "SELECT base FROM loot_wishlist WHERE uuid = @u ORDER BY rowid");
    SqlBindString(q, "@u", GetObjectUUID(oPC));
    while (SqlStep(q))
        sList += IntToString(SqlGetInt(q, 0)) + "|";
    SetLocalString(oPC, LOOT_WISH, sList);
    SetLocalInt(oPC, LOOT_WISH_OK, TRUE);
    return sList;
}

// The cached list ("|row|row|", may hold "|-1|"), loading it on first use.
string Loot_WishGet(object oPC)
{
    if (!GetLocalInt(oPC, LOOT_WISH_OK)) return Loot_WishLoad(oPC);
    return GetLocalString(oPC, LOOT_WISH);
}

int Loot_WishHas(object oPC, int nBase)
{
    return FindSubString(Loot_WishGet(oPC), "|" + IntToString(nBase) + "|") >= 0;
}

int Loot_WishAutoOn(object oPC)
{
    return !Loot_WishHas(oPC, LOOT_WISH_AUTO_OFF);
}

// Number of picked base items (the Auto sentinel does not count).
int Loot_WishCount(object oPC)
{
    string s = Loot_WishGet(oPC);
    int n = 0;
    int i;
    for (i = 1; i < GetStringLength(s); i++)
        if (GetSubString(s, i, 1) == "|") n++;
    return n - !Loot_WishAutoOn(oPC);
}

void Loot_WishAdd(object oPC, int nBase)
{
    sqlquery q = SqlPrepareQueryCampaign(LOOT_DB,
        "INSERT OR IGNORE INTO loot_wishlist (uuid, base) VALUES (@u, @b)");
    SqlBindString(q, "@u", GetObjectUUID(oPC));
    SqlBindInt(q, "@b", nBase);
    SqlStep(q);
    Loot_WishLoad(oPC);
}

void Loot_WishRemove(object oPC, int nBase)
{
    sqlquery q = SqlPrepareQueryCampaign(LOOT_DB,
        "DELETE FROM loot_wishlist WHERE uuid = @u AND base = @b");
    SqlBindString(q, "@u", GetObjectUUID(oPC));
    SqlBindInt(q, "@b", nBase);
    SqlStep(q);
    Loot_WishLoad(oPC);
}

// Remove every pick; the Auto setting is kept.
void Loot_WishClear(object oPC)
{
    sqlquery q = SqlPrepareQueryCampaign(LOOT_DB,
        "DELETE FROM loot_wishlist WHERE uuid = @u AND base >= 0");
    SqlBindString(q, "@u", GetObjectUUID(oPC));
    SqlStep(q);
    Loot_WishLoad(oPC);
}

void Loot_WishSetAuto(object oPC, int bOn)
{
    if (bOn) Loot_WishRemove(oPC, LOOT_WISH_AUTO_OFF);
    else     Loot_WishAdd(oPC, LOOT_WISH_AUTO_OFF);
}

// ---------------------------------------------------------------------------
// Phase 7: Shard of Fate bonus-roll lockout (lo-fate-token)
// ---------------------------------------------------------------------------
// One bonus roll per character (GetObjectUUID) per boss resref per rolling
// nLockout seconds (loot/tokens.json fate.lockout_s, admin 2026-11-06). Read
// only at a boss death and on a Spend click, so the per-call query is cheap.

// Seconds until oPC may take another bonus roll on sBoss; 0 = free now.
int Loot_FateLockedFor(object oPC, string sBoss, int nLockout)
{
    sqlquery q = SqlPrepareQueryCampaign(LOOT_DB,
        "SELECT at + @n - CAST(strftime('%s','now') AS INTEGER) FROM loot_fate_lockout " +
        "WHERE uuid = @u AND boss = @b");
    SqlBindInt(q, "@n", nLockout);
    SqlBindString(q, "@u", GetObjectUUID(oPC));
    SqlBindString(q, "@b", sBoss);
    if (!SqlStep(q)) return 0;
    int nLeft = SqlGetInt(q, 0);
    return nLeft > 0 ? nLeft : 0;
}

// Record that oPC took a bonus roll on sBoss now.
void Loot_FateLock(object oPC, string sBoss)
{
    sqlquery q = SqlPrepareQueryCampaign(LOOT_DB,
        "INSERT OR REPLACE INTO loot_fate_lockout (uuid, boss, at) " +
        "VALUES (@u, @b, CAST(strftime('%s','now') AS INTEGER))");
    SqlBindString(q, "@u", GetObjectUUID(oPC));
    SqlBindString(q, "@b", sBoss);
    SqlStep(q);
}

// Loot Lab: clear every lockout oPC holds. Returns how many were cleared.
int Loot_FateClear(object oPC)
{
    sqlquery q = SqlPrepareQueryCampaign(LOOT_DB,
        "SELECT COUNT(*) FROM loot_fate_lockout WHERE uuid = @u");
    SqlBindString(q, "@u", GetObjectUUID(oPC));
    int n = SqlStep(q) ? SqlGetInt(q, 0) : 0;
    q = SqlPrepareQueryCampaign(LOOT_DB, "DELETE FROM loot_fate_lockout WHERE uuid = @u");
    SqlBindString(q, "@u", GetObjectUUID(oPC));
    SqlStep(q);
    return n;
}
