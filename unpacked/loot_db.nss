// loot_db.nss - the lootdb campaign DB (Season 3 rolled loot).
//
// Roadmap: loot-overhaul epic, lo-loot-core (Phase 2).  Design:
// docs.manual/Draft/Loot-Overhaul.html.
//
// Phase 2 owns one table, loot_roll_log: balance telemetry for the rolls that
// matter (every Loot Lab roll, and any Epic-or-better roll from anywhere).  It
// is deliberately NOT every roll - a synchronous SQLite commit per chest item
// would be felt as server lag once Phase 3 puts chests on Loot_Roll.
// Phase 6 (wishlist) and Phase 7 (Fate token lockout) add their tables here.
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
}

// Record one roll.  sItem is the rolled name (or the named-pool resref);
// nValue is the engine gold value the budget was checked against (-1 = named).
void Loot_LogRoll(string sSource, string sProfile, int nLvl, int nRarity,
                  int nBase, string sItem, int nValue, object oBeneficiary)
{
    if (sSource != "lab" && nRarity < LOOT_LOG_MIN_RARITY)
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
