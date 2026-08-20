// merit_db.nss - Merit Award System database helpers
//
// Campaign DB: "meritdb" (SQLite)
// Schema:  players(cdkey PK, name, last_login, bugs, exploits, features,
//                  uat, merit_spent)
//
// Merit rates: defect=1pt  exploit=3pts  feature=2pts  uat=1pt
//
// `uat` credits a player for helping VALIDATE a fix, which is independent of
// who reported it: several players can be credited for the same roadmap item,
// and none of them need be the submitter.

const string MERIT_DB            = "meritdb";
const int    MERIT_BUG_VALUE     = 1;
const int    MERIT_EXPLOIT_VALUE = 3;
const int    MERIT_FEATURE_VALUE = 2;
const int    MERIT_UAT_VALUE     = 1;

const int MERIT_COST_1 = 5;
const int MERIT_COST_2 = 10;
const int MERIT_COST_3 = 20;
const int MERIT_COST_4 = 35;
const int MERIT_COST_5 = 50;

// ------------------------------------------------------------
// Schema

void Merit_InitDb()
{
    sqlquery q = SqlPrepareQueryCampaign(MERIT_DB,
        "CREATE TABLE IF NOT EXISTS players (" +
        "cdkey TEXT PRIMARY KEY," +
        "name TEXT," +
        "last_login TEXT," +
        "bugs INTEGER DEFAULT 0," +
        "exploits INTEGER DEFAULT 0," +
        "features INTEGER DEFAULT 0," +
        "uat INTEGER DEFAULT 0," +
        "merit_spent INTEGER DEFAULT 0)");
    SqlStep(q);

    // Redemption requests. Escrow model: cost is debited (added to
    // players.merit_spent) the moment a row is inserted as 'pending', and
    // refunded only if the row is 'cancelled'. 'fulfilled' rows keep the debit.
    sqlquery qr = SqlPrepareQueryCampaign(MERIT_DB,
        "CREATE TABLE IF NOT EXISTS redemptions (" +
        "id INTEGER PRIMARY KEY AUTOINCREMENT," +
        "cdkey TEXT NOT NULL," +
        "player_name TEXT," +
        "reward_id INTEGER NOT NULL," +
        "reward_label TEXT," +
        "cost INTEGER NOT NULL," +
        "needs_dm INTEGER NOT NULL DEFAULT 1," +
        "status TEXT NOT NULL DEFAULT 'pending'," +     // pending|fulfilled|cancelled
        "requested_at TEXT NOT NULL DEFAULT (datetime('now'))," +
        "resolved_by TEXT," +
        "resolved_at TEXT," +
        "item_tag TEXT)");                              // unique serial tag of a granted item
    SqlStep(qr);

    // Migration: older DBs created the redemptions table before item_tag
    // existed; CREATE TABLE IF NOT EXISTS won't alter it, so add the column
    // when missing. PRAGMA table_info is checked first to avoid logging a SQL
    // error every boot from re-running ALTER on a table that already has it.
    int bHasItemTag = FALSE;
    sqlquery qp = SqlPrepareQueryCampaign(MERIT_DB, "PRAGMA table_info(redemptions)");
    while (SqlStep(qp))
        if (SqlGetString(qp, 1) == "item_tag") { bHasItemTag = TRUE; break; }
    if (!bHasItemTag)
    {
        sqlquery qa = SqlPrepareQueryCampaign(MERIT_DB,
            "ALTER TABLE redemptions ADD COLUMN item_tag TEXT");
        SqlStep(qa);
    }

    // Migration: the players table predates the `uat` column. Same shape as the
    // item_tag migration above - CREATE TABLE IF NOT EXISTS will not add a
    // column to a table that already exists, and meritdb is the SHARED
    // cross-season database, so this is the only thing that backfills it.
    int bHasUat = FALSE;
    sqlquery qpu = SqlPrepareQueryCampaign(MERIT_DB, "PRAGMA table_info(players)");
    while (SqlStep(qpu))
        if (SqlGetString(qpu, 1) == "uat") { bHasUat = TRUE; break; }
    if (!bHasUat)
    {
        sqlquery qau = SqlPrepareQueryCampaign(MERIT_DB,
            "ALTER TABLE players ADD COLUMN uat INTEGER DEFAULT 0");
        SqlStep(qau);
    }

    // Transaction ledger - every merit movement (spend/refund/award) with the
    // resulting available balance, for audit and recovery. Never pruned.
    sqlquery ql = SqlPrepareQueryCampaign(MERIT_DB,
        "CREATE TABLE IF NOT EXISTS merit_ledger (" +
        "id INTEGER PRIMARY KEY AUTOINCREMENT," +
        "cdkey TEXT NOT NULL," +
        "player_name TEXT," +
        "delta INTEGER NOT NULL," +          // <0 spent, >0 refunded/awarded
        "balance_after INTEGER," +
        "reason TEXT," +
        "redemption_id INTEGER," +
        "created_at TEXT NOT NULL DEFAULT (datetime('now')))");
    SqlStep(ql);
}

// ------------------------------------------------------------
// Login tracking

void Merit_RecordLogin(object oPC)
{
    sqlquery q = SqlPrepareQueryCampaign(MERIT_DB,
        "INSERT INTO players(cdkey, name, last_login) VALUES(@k, @n, datetime('now'))" +
        " ON CONFLICT(cdkey) DO UPDATE SET name=excluded.name, last_login=excluded.last_login");
    SqlBindString(q, "@k", GetPCPublicCDKey(oPC));
    SqlBindString(q, "@n", GetPCPlayerName(oPC));
    SqlStep(q);
}

// Sent on login only when the player has at least one contribution.
void Merit_LoginMessage(object oPC)
{
    sqlquery q = SqlPrepareQueryCampaign(MERIT_DB,
        "SELECT bugs, exploits, features, merit_spent, uat FROM players WHERE cdkey=@k");
    SqlBindString(q, "@k", GetPCPublicCDKey(oPC));
    if (!SqlStep(q)) return;

    int nBugs  = SqlGetInt(q, 0);
    int nExp   = SqlGetInt(q, 1);
    int nFtr   = SqlGetInt(q, 2);
    int nSpent = SqlGetInt(q, 3);
    int nUat   = SqlGetInt(q, 4);

    if (nBugs + nExp + nFtr + nUat == 0) return;

    int nEarned = nBugs  * MERIT_BUG_VALUE
                + nExp   * MERIT_EXPLOIT_VALUE
                + nFtr   * MERIT_FEATURE_VALUE
                + nUat   * MERIT_UAT_VALUE;
    int nAvail  = nEarned - nSpent;

    SendMessageToPC(oPC,
        "\n[Merit] Thank you for your contributions to this world!\n" +
        "  Defects reported:    " + IntToString(nBugs) + "\n" +
        "  Exploits reported:   " + IntToString(nExp)  + "\n" +
        "  Features implemented:" + IntToString(nFtr)  + "\n" +
        "  Fixes validated:     " + IntToString(nUat)  + "\n" +
        "Merit balance: " + IntToString(nAvail) + " pts available to spend.\n" +
        "Visit Barliman the barkeep in the Prancing Pony to redeem rewards.");
}

// ------------------------------------------------------------
// Awarding

void Merit_AwardBug(string sCdKey)
{
    sqlquery q = SqlPrepareQueryCampaign(MERIT_DB,
        "UPDATE players SET bugs=bugs+1 WHERE cdkey=@k");
    SqlBindString(q, "@k", sCdKey);
    SqlStep(q);
}

void Merit_AwardExploit(string sCdKey)
{
    sqlquery q = SqlPrepareQueryCampaign(MERIT_DB,
        "UPDATE players SET exploits=exploits+1 WHERE cdkey=@k");
    SqlBindString(q, "@k", sCdKey);
    SqlStep(q);
}

void Merit_AwardFeature(string sCdKey)
{
    sqlquery q = SqlPrepareQueryCampaign(MERIT_DB,
        "UPDATE players SET features=features+1 WHERE cdkey=@k");
    SqlBindString(q, "@k", sCdKey);
    SqlStep(q);
}

// Credit one UAT / validation pass. Unlike the three above this is not tied to
// reporting an idea - it pays whoever helped verify the fix.
void Merit_AwardUat(string sCdKey)
{
    sqlquery q = SqlPrepareQueryCampaign(MERIT_DB,
        "UPDATE players SET uat=uat+1 WHERE cdkey=@k");
    SqlBindString(q, "@k", sCdKey);
    SqlStep(q);
}

// ------------------------------------------------------------
// Balance

int Merit_Available(string sCdKey)
{
    sqlquery q = SqlPrepareQueryCampaign(MERIT_DB,
        "SELECT bugs, exploits, features, merit_spent, uat FROM players WHERE cdkey=@k");
    SqlBindString(q, "@k", sCdKey);
    if (!SqlStep(q)) return 0;
    int nBugs  = SqlGetInt(q, 0);
    int nExp   = SqlGetInt(q, 1);
    int nFtr   = SqlGetInt(q, 2);
    int nSpent = SqlGetInt(q, 3);
    int nUat   = SqlGetInt(q, 4);
    return nBugs  * MERIT_BUG_VALUE
         + nExp   * MERIT_EXPLOIT_VALUE
         + nFtr   * MERIT_FEATURE_VALUE
         + nUat   * MERIT_UAT_VALUE
         - nSpent;
}

// Append a ledger row. nDelta < 0 = spent, > 0 = refunded/awarded. Records the
// available balance *after* the movement, so call this once the underlying
// counters (merit_spent / bugs / exploits / features) are already updated.
// Pass nRedemptionId = 0 when not tied to a redemption. If sName is "", the
// player's stored name is looked up.
void Merit_Ledger(string sCdKey, string sName, int nDelta, string sReason, int nRedemptionId)
{
    if (sName == "")
    {
        sqlquery qn = SqlPrepareQueryCampaign(MERIT_DB,
            "SELECT name FROM players WHERE cdkey=@k");
        SqlBindString(qn, "@k", sCdKey);
        if (SqlStep(qn)) sName = SqlGetString(qn, 0);
    }

    sqlquery q = SqlPrepareQueryCampaign(MERIT_DB,
        "INSERT INTO merit_ledger(cdkey, player_name, delta, balance_after, reason, redemption_id)"
        + " VALUES(@k, @n, @d, @b, @r, @i)");
    SqlBindString(q, "@k", sCdKey);
    SqlBindString(q, "@n", sName);
    SqlBindInt(q, "@d", nDelta);
    SqlBindInt(q, "@b", Merit_Available(sCdKey));
    SqlBindString(q, "@r", sReason);
    SqlBindInt(q, "@i", nRedemptionId);
    SqlStep(q);
}

void Merit_Spend(string sCdKey, int nCost)
{
    sqlquery q = SqlPrepareQueryCampaign(MERIT_DB,
        "UPDATE players SET merit_spent=merit_spent+@c WHERE cdkey=@k");
    SqlBindInt(q, "@c", nCost);
    SqlBindString(q, "@k", sCdKey);
    SqlStep(q);
}

// Refund escrowed merit (e.g. a cancelled redemption). Clamps merit_spent at 0
// so a double-cancel or bookkeeping slip can never drive it negative.
void Merit_Refund(string sCdKey, int nCost)
{
    if (nCost <= 0) return;
    sqlquery q = SqlPrepareQueryCampaign(MERIT_DB,
        "UPDATE players SET merit_spent=MAX(0, merit_spent-@c) WHERE cdkey=@k");
    SqlBindInt(q, "@c", nCost);
    SqlBindString(q, "@k", sCdKey);
    SqlStep(q);
}

// ------------------------------------------------------------
// NPC conversation tokens (5020-5029)
// Call from reply action scripts; tokens are set before the next entry renders.

void Merit_SetNpcTokens(object oPC)
{
    sqlquery q = SqlPrepareQueryCampaign(MERIT_DB,
        "SELECT bugs, exploits, features, merit_spent, uat FROM players WHERE cdkey=@k");
    SqlBindString(q, "@k", GetPCPublicCDKey(oPC));

    int nBugs  = 0;
    int nExp   = 0;
    int nFtr   = 0;
    int nSpent = 0;
    int nUat   = 0;
    if (SqlStep(q))
    {
        nBugs  = SqlGetInt(q, 0);
        nExp   = SqlGetInt(q, 1);
        nFtr   = SqlGetInt(q, 2);
        nSpent = SqlGetInt(q, 3);
        nUat   = SqlGetInt(q, 4);
    }

    int nBugPts = nBugs  * MERIT_BUG_VALUE;
    int nExpPts = nExp   * MERIT_EXPLOIT_VALUE;
    int nFtrPts = nFtr   * MERIT_FEATURE_VALUE;
    int nUatPts = nUat   * MERIT_UAT_VALUE;
    int nEarned = nBugPts + nExpPts + nFtrPts + nUatPts;
    int nAvail  = nEarned - nSpent;

    SetCustomToken(5020, IntToString(nBugs));
    SetCustomToken(5021, IntToString(nExp));
    SetCustomToken(5022, IntToString(nFtr));
    SetCustomToken(5023, IntToString(nBugPts));
    SetCustomToken(5024, IntToString(nExpPts));
    SetCustomToken(5025, IntToString(nFtrPts));
    SetCustomToken(5026, IntToString(nEarned));
    SetCustomToken(5027, IntToString(nAvail));
    SetCustomToken(5028, IntToString(nUat));
    SetCustomToken(5029, IntToString(nUatPts));
}

// ------------------------------------------------------------
// DM emote-wand player list (tokens 5001-5010)
// Call from reply action scripts; tokens are set before E_PLAYER_LIST renders.

void Merit_BuildPage(object oDM)
{
    int nOff = GetLocalInt(oDM, "merit_page_off");

    sqlquery qCount = SqlPrepareQueryCampaign(MERIT_DB, "SELECT COUNT(*) FROM players");
    int nTotal = 0;
    if (SqlStep(qCount)) nTotal = SqlGetInt(qCount, 0);
    SetLocalInt(oDM, "merit_page_total", nTotal);

    int nPages = (nTotal + 8) / 9;
    if (nPages == 0) nPages = 1;
    int nPage = nOff / 9 + 1;
    SetCustomToken(5010, "Page " + IntToString(nPage) + " of " + IntToString(nPages));

    int i;
    for (i = 0; i < 9; i++)
    {
        DeleteLocalString(oDM, "merit_slot_" + IntToString(i) + "_cdkey");
        DeleteLocalString(oDM, "merit_slot_" + IntToString(i) + "_name");
        SetCustomToken(5001 + i, "(empty)");
    }

    sqlquery q = SqlPrepareQueryCampaign(MERIT_DB,
        "SELECT cdkey, name, bugs, exploits, features, merit_spent, uat" +
        " FROM players ORDER BY last_login DESC LIMIT 9 OFFSET @off");
    SqlBindInt(q, "@off", nOff);

    i = 0;
    while (SqlStep(q) && i < 9)
    {
        string sCdKey  = SqlGetString(q, 0);
        string sName   = SqlGetString(q, 1);
        int nBugs      = SqlGetInt(q, 2);
        int nExp       = SqlGetInt(q, 3);
        int nFtr       = SqlGetInt(q, 4);
        int nSpent     = SqlGetInt(q, 5);
        int nUat       = SqlGetInt(q, 6);
        int nAvail     = nBugs  * MERIT_BUG_VALUE
                       + nExp   * MERIT_EXPLOIT_VALUE
                       + nFtr   * MERIT_FEATURE_VALUE
                       + nUat   * MERIT_UAT_VALUE
                       - nSpent;

        SetLocalString(oDM, "merit_slot_" + IntToString(i) + "_cdkey", sCdKey);
        SetLocalString(oDM, "merit_slot_" + IntToString(i) + "_name",  sName);

        string sLabel = sName
            + " [D:" + IntToString(nBugs)
            + " E:" + IntToString(nExp)
            + " F:" + IntToString(nFtr)
            + " U:" + IntToString(nUat)
            + " bal:" + IntToString(nAvail) + "]";
        SetCustomToken(5001 + i, sLabel);
        i++;
    }
}
