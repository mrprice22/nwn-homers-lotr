// cp_db -- persistence for the Crash Party event.
//
// Campaign DB "crashpartydb". Three tables, all created idempotently by
// CP_InitDb(), which is called ONCE from onmoduleload.nss.
//
//   cp_player  per-character tankard sip count (the drinking leaderboard)
//   cp_grant   per-character "already received this item" flags for the wave dispenser
//   cp_state   scalar world state; currently just the peak-concurrent record
//
// ## Why a table rather than PC local ints
//
// The dispenser MUST NOT re-grant on relog, and locals on the PC are session
// scoped -- that is exactly the relog-farm the gondor-scribe fix closed by moving
// its guard into questcddb (see quest_cd_inc.nss). Same reasoning, own database:
// the party's data stays self-contained and can be wiped without touching quest
// cooldowns.
//
// ## DDL runs at module load, never on the login frame
//
// CREATE TABLE on mod_cliententer is felt as login lag (see CLAUDE-*.md). All of
// it happens once, in onmoduleload.
//
// Table names avoid NWN:EE's reserved campaign-DB names (meta, db, migrations),
// which fail silently per-statement with SQLITE_AUTH.

const string CP_DB = "crashpartydb";

void   CP_InitDb();
string CP_Ident(object oPC);
int    CP_HasGrant(object oPC, string sItem);
void   CP_MarkGrant(object oPC, string sItem);
int    CP_AddSips(object oPC, int nHowMany = 1);
int    CP_GetSips(object oPC);
string CP_TopSips(int nRows = 5);
int    CP_Now();
int    CP_GetPeak();
void   CP_SetPeak(int nPeak);

void CP_InitDb()
{
    sqlquery q;

    q = SqlPrepareQueryCampaign(CP_DB,
        "CREATE TABLE IF NOT EXISTS cp_player (" +
        "ident TEXT PRIMARY KEY," +
        "char_name TEXT," +
        "cdkey TEXT," +
        "sips INTEGER NOT NULL DEFAULT 0)");
    SqlStep(q);

    q = SqlPrepareQueryCampaign(CP_DB,
        "CREATE TABLE IF NOT EXISTS cp_grant (" +
        "ident TEXT NOT NULL," +
        "item TEXT NOT NULL," +
        "granted_at INTEGER NOT NULL DEFAULT 0," +
        "PRIMARY KEY (ident, item))");
    SqlStep(q);

    q = SqlPrepareQueryCampaign(CP_DB,
        "CREATE TABLE IF NOT EXISTS cp_state (" +
        "k TEXT PRIMARY KEY," +
        "v INTEGER NOT NULL)");
    SqlStep(q);
}

// Character identity. Same reasoning as QCD_Ident in quest_cd_inc.nss: a UUID is
// minted once and persists in the .bic, but an unsaved character can hand back an
// empty string, and an empty key makes every lookup miss -- which reads in game as
// "the once-ever grant is broken" while the live server is fine.
string CP_Ident(object oPC)
{
    string sUuid = GetObjectUUID(oPC);
    if (sUuid != "") return sUuid;
    return "k:" + GetPCPublicCDKey(oPC) + "|" + GetName(oPC);
}

int CP_HasGrant(object oPC, string sItem)
{
    sqlquery q = SqlPrepareQueryCampaign(CP_DB,
        "SELECT 1 FROM cp_grant WHERE ident=@i AND item=@t");
    SqlBindString(q, "@i", CP_Ident(oPC));
    SqlBindString(q, "@t", sItem);
    return SqlStep(q);
}

void CP_MarkGrant(object oPC, string sItem)
{
    sqlquery q = SqlPrepareQueryCampaign(CP_DB,
        "INSERT INTO cp_grant (ident, item, granted_at) " +
        "VALUES (@i, @t, CAST(strftime('%s','now') AS INTEGER)) " +
        "ON CONFLICT(ident, item) DO NOTHING");
    SqlBindString(q, "@i", CP_Ident(oPC));
    SqlBindString(q, "@t", sItem);
    SqlStep(q);
}

// Add to this character's sip count and return the new total.
int CP_AddSips(object oPC, int nHowMany = 1)
{
    sqlquery q = SqlPrepareQueryCampaign(CP_DB,
        "INSERT INTO cp_player (ident, char_name, cdkey, sips) " +
        "VALUES (@i, @n, @k, @c) " +
        "ON CONFLICT(ident) DO UPDATE SET " +
        "sips = sips + @c, char_name = @n");
    SqlBindString(q, "@i", CP_Ident(oPC));
    SqlBindString(q, "@n", GetName(oPC));
    SqlBindString(q, "@k", GetPCPublicCDKey(oPC));
    SqlBindInt(q, "@c", nHowMany);
    SqlStep(q);
    return CP_GetSips(oPC);
}

int CP_GetSips(object oPC)
{
    sqlquery q = SqlPrepareQueryCampaign(CP_DB,
        "SELECT sips FROM cp_player WHERE ident=@i");
    SqlBindString(q, "@i", CP_Ident(oPC));
    return SqlStep(q) ? SqlGetInt(q, 0) : 0;
}

// Leaderboard rows, newline separated, already numbered. Empty string when
// nobody has taken a drink yet -- the caller decides what to say about that.
string CP_TopSips(int nRows = 5)
{
    sqlquery q = SqlPrepareQueryCampaign(CP_DB,
        "SELECT char_name, sips FROM cp_player " +
        "WHERE sips > 0 ORDER BY sips DESC, char_name ASC LIMIT @l");
    SqlBindInt(q, "@l", nRows);

    string sOut = "";
    int nRank = 0;
    while (SqlStep(q))
    {
        nRank++;
        sOut += IntToString(nRank) + ". " + SqlGetString(q, 0)
              + " -- " + IntToString(SqlGetInt(q, 1)) + "\n";
    }
    return sOut;
}

// Real-world "now" as unix-epoch seconds, from SQLite rather than the game clock
// (the game clock runs at its own speed and is not what "a few minutes" means to
// a player). Same trick as QCD_Now in quest_cd_inc.nss.
int CP_Now()
{
    sqlquery q = SqlPrepareQueryCampaign(CP_DB,
        "SELECT CAST(strftime('%s','now') AS INTEGER)");
    return SqlStep(q) ? SqlGetInt(q, 0) : 0;
}

int CP_GetPeak()
{
    sqlquery q = SqlPrepareQueryCampaign(CP_DB,
        "SELECT v FROM cp_state WHERE k='peak'");
    return SqlStep(q) ? SqlGetInt(q, 0) : 0;
}

void CP_SetPeak(int nPeak)
{
    sqlquery q = SqlPrepareQueryCampaign(CP_DB,
        "INSERT INTO cp_state (k, v) VALUES ('peak', @v) " +
        "ON CONFLICT(k) DO UPDATE SET v = @v");
    SqlBindInt(q, "@v", nPeak);
    SqlStep(q);
}
