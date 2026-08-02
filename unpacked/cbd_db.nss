// cbd_db.nss — Combat Dummy leaderboard ("Hall of Champions") database.
//
// Campaign DB "combatdummydb" (file database/combatdummydb.sqlite3), table
// sessions: one row per completed 10-round test.
//
//   id, cdkey, player_name, uuid, char_name, dpr, total_damage, rounds, at
//
// Identity is split the same way as bst_db.nss: `uuid` (GetObjectUUID) is the
// CHARACTER, `cdkey` (GetPCPublicCDKey) is the ACCOUNT. Attacks per round are
// deliberately NOT stored — they are a per-session diagnostic, not a score.
//
// The sign (cbd_sign.dlg) browses three views, 10 rows to a page:
//   mode 1  this account's best result per character, top 10
//   mode 2  this account's 10 most recent results
//   mode 3  server-wide top 20, ONE ROW PER ACCOUNT (an account's single best
//           result across all its characters), paged 10 + 10
//
// Custom tokens: 6400 header, 6401-6410 rows, 6411 footer.
// Per-PC locals: "cbd_mode", "cbd_off", "cbd_total".

const string CBD_DB       = "combatdummydb";
const int    CBD_TOK_HEAD = 6400;
const int    CBD_TOK_ROW0 = 6401;
const int    CBD_TOK_FOOT = 6411;
const int    CBD_PAGE     = 10;   // rows per page
const int    CBD_TOP_MAX  = 20;   // server-wide leaderboard depth

void Cbd_InitDb()
{
    sqlquery q = SqlPrepareQueryCampaign(CBD_DB,
        "CREATE TABLE IF NOT EXISTS sessions (" +
        "id INTEGER PRIMARY KEY AUTOINCREMENT," +
        "cdkey TEXT NOT NULL," +
        "player_name TEXT," +
        "uuid TEXT NOT NULL," +
        "char_name TEXT," +
        "dpr REAL NOT NULL," +
        "total_damage INTEGER NOT NULL," +
        "rounds INTEGER NOT NULL," +
        "at TEXT NOT NULL DEFAULT (datetime('now')))");
    SqlStep(q);

    q = SqlPrepareQueryCampaign(CBD_DB,
        "CREATE INDEX IF NOT EXISTS idx_sessions_cdkey ON sessions(cdkey)");
    SqlStep(q);

    q = SqlPrepareQueryCampaign(CBD_DB,
        "CREATE INDEX IF NOT EXISTS idx_sessions_dpr ON sessions(dpr DESC)");
    SqlStep(q);
}

void Cbd_Record(object oPC, float fDpr, int nTotalDamage, int nRounds)
{
    sqlquery q = SqlPrepareQueryCampaign(CBD_DB,
        "INSERT INTO sessions (cdkey, player_name, uuid, char_name, dpr," +
        " total_damage, rounds) VALUES (@k, @p, @u, @c, @d, @t, @r)");
    SqlBindString(q, "@k", GetPCPublicCDKey(oPC));
    SqlBindString(q, "@p", GetPCPlayerName(oPC));
    SqlBindString(q, "@u", GetObjectUUID(oPC));
    SqlBindString(q, "@c", GetName(oPC));
    SqlBindFloat (q, "@d", fDpr);
    SqlBindInt   (q, "@t", nTotalDamage);
    SqlBindInt   (q, "@r", nRounds);
    SqlStep(q);
}

// ---------------------------------------------------------------------------
// Browsing

string Cbd_ModeTitle(int nMode)
{
    if (nMode == 1) return "Your account — best result per character";
    if (nMode == 2) return "Your account — 10 most recent tests";
    return "Server-wide — top " + IntToString(CBD_TOP_MAX) + " (best per player)";
}

// One "keep only the best row" filter, written once. The correlated NOT EXISTS
// picks the single winning row per partition (and its own char_name/date), which
// a GROUP BY + MAX(dpr) cannot promise.
string Cbd_BestRowFilter(string sPartitionCol)
{
    return " AND NOT EXISTS (SELECT 1 FROM sessions b WHERE b." +
           sPartitionCol + " = s." + sPartitionCol +
           " AND (b.dpr > s.dpr OR (b.dpr = s.dpr AND b.id < s.id)))";
}

string Cbd_Sql(int nMode, int bCount)
{
    string sCols = bCount ? "COUNT(*)"
                          : "player_name, char_name, dpr, substr(at, 1, 10)";
    string sSql  = "SELECT " + sCols + " FROM sessions s WHERE 1=1";

    if (nMode == 1)
        sSql += " AND s.cdkey = @k" + Cbd_BestRowFilter("uuid");
    else if (nMode == 2)
        sSql += " AND s.cdkey = @k";
    else
        sSql += Cbd_BestRowFilter("cdkey");

    if (bCount) return sSql;

    if (nMode == 2) sSql += " ORDER BY s.id DESC";
    else            sSql += " ORDER BY s.dpr DESC, s.id ASC";

    return sSql + " LIMIT @lim OFFSET @off";
}

// How many rows this mode can show in total (capped by the published depth).
int Cbd_Total(object oPC, int nMode)
{
    sqlquery q = SqlPrepareQueryCampaign(CBD_DB, Cbd_Sql(nMode, TRUE));
    if (nMode == 1 || nMode == 2) SqlBindString(q, "@k", GetPCPublicCDKey(oPC));

    int nTotal = 0;
    if (SqlStep(q)) nTotal = SqlGetInt(q, 0);

    int nCap = (nMode == 3) ? CBD_TOP_MAX : CBD_PAGE;
    return (nTotal > nCap) ? nCap : nTotal;
}

// Fill the page tokens for the PC's current mode/offset.
void Cbd_BuildPage(object oPC)
{
    int nMode = GetLocalInt(oPC, "cbd_mode");
    int nOff  = GetLocalInt(oPC, "cbd_off");

    int nTotal = Cbd_Total(oPC, nMode);
    SetLocalInt(oPC, "cbd_total", nTotal);

    SetCustomToken(CBD_TOK_HEAD, Cbd_ModeTitle(nMode));
    int i;
    for (i = 0; i < CBD_PAGE; i++) SetCustomToken(CBD_TOK_ROW0 + i, "");

    if (nTotal <= 0)
    {
        SetCustomToken(CBD_TOK_ROW0, "   (no results recorded yet)");
        SetCustomToken(CBD_TOK_FOOT, "");
        return;
    }

    // Never read past the published depth, even if the table holds more.
    int nLimit = nTotal - nOff;
    if (nLimit > CBD_PAGE) nLimit = CBD_PAGE;

    sqlquery q = SqlPrepareQueryCampaign(CBD_DB, Cbd_Sql(nMode, FALSE));
    if (nMode == 1 || nMode == 2) SqlBindString(q, "@k", GetPCPublicCDKey(oPC));
    SqlBindInt(q, "@lim", nLimit);
    SqlBindInt(q, "@off", nOff);

    i = 0;
    while (SqlStep(q) && i < CBD_PAGE)
    {
        string sRow = IntToString(nOff + i + 1) + ". " +
                      SqlGetString(q, 0) + "  |  " +      // player account
                      SqlGetString(q, 1) + "  |  " +      // character
                      FloatToString(SqlGetFloat(q, 2), 0, 1) + " DPR  |  " +
                      SqlGetString(q, 3);                 // date
        SetCustomToken(CBD_TOK_ROW0 + i, sRow);
        i++;
    }

    SetCustomToken(CBD_TOK_FOOT, "Showing " + IntToString(nOff + 1) + "-" +
                   IntToString(nOff + i) + " of " + IntToString(nTotal) + ".");
}

void Cbd_OpenMode(object oPC, int nMode)
{
    SetLocalInt(oPC, "cbd_mode", nMode);
    SetLocalInt(oPC, "cbd_off", 0);
    Cbd_BuildPage(oPC);
}
