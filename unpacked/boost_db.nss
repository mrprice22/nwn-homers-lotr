// boost_db.nss -- Temporary 2x gold/XP "premium boost" subscriptions.
//
// Campaign DB: "boostdb" (SQLite). Backs merit redemptions 201-204
// (see merit_redeem.nss). A purchase enqueues a subscription; the buff
// multiplies creature/quest gold & XP (never bank withdrawals or item sales --
// that scoping lives at the reward call sites, not here). Read boost_inc.nss for
// how the multiplier is applied.
//
// Two independent chains, both "one active at a time, rest queued":
//   * server chain  -- all server-wide subs across all buyers. Always burns real
//                     time while it has any remaining; "server on" the whole time.
//   * personal chain (per CD key) -- that player's own subs. Burns real time ONLY
//                     while the server chain is NOT active (a live server buff
//                     pauses everyone's personal clock, since it already grants 2x).
//
// Time is settled lazily (no DelayCommand timers): Boost_Reconcile() drains
// remaining_sec by the wall-clock elapsed since last_reconciled, promotes the new
// head of each chain, and recomputes two cached absolute expiry timestamps:
//   boost_state.server_active_until            = now + sum of (server remaining)
//   player_boost.personal_active_until[cdkey]  = now + sum of (server remaining)
//                                                    + sum of (that player's personal remaining)
// Those absolutes stay correct as plain time passes (time only shifts remaining
// seconds around; it never changes a chain's contents), so the hot path
// (Boost_Mult in boost_inc.nss) just compares them to now -- no per-kill reconcile.
// They are only recomputed when a chain changes: on purchase and on login.

const string BOOST_DB   = "boostdb";
const int    BOOST_MULT = 2;         // "take the higher": any active buff => 2x, never 4x.

// ------------------------------------------------------------
// Small helpers

int Boost_Now()
{
    sqlquery q = SqlPrepareQueryCampaign(BOOST_DB, "SELECT CAST(strftime('%s','now') AS INTEGER)");
    return SqlStep(q) ? SqlGetInt(q, 0) : 0;
}

// Human date for a unix epoch, e.g. "2026-07-15 04:12".
string Boost_FmtDate(int nEpoch)
{
    sqlquery q = SqlPrepareQueryCampaign(BOOST_DB,
        "SELECT strftime('%Y-%m-%d %H:%M', @e, 'unixepoch')");
    SqlBindInt(q, "@e", nEpoch);
    return SqlStep(q) ? SqlGetString(q, 0) : "";
}

// ------------------------------------------------------------
// Schema

void Boost_InitDb()
{
    sqlquery q = SqlPrepareQueryCampaign(BOOST_DB,
        "CREATE TABLE IF NOT EXISTS boost_sub (" +
        "id INTEGER PRIMARY KEY AUTOINCREMENT," +
        "scope TEXT NOT NULL," +              // 'server' | 'personal'
        "cdkey TEXT NOT NULL," +              // owner (personal) / buyer (server)
        "buyer_name TEXT," +
        "dur_sec INTEGER NOT NULL," +         // original length
        "remaining_sec INTEGER NOT NULL," +   // decremented on reconcile
        "status TEXT NOT NULL DEFAULT 'pending'," +   // active | pending | done
        "created_at TEXT NOT NULL DEFAULT (datetime('now')))");
    SqlStep(q);

    sqlquery qs = SqlPrepareQueryCampaign(BOOST_DB,
        "CREATE TABLE IF NOT EXISTS boost_state (" +
        "id INTEGER PRIMARY KEY CHECK(id=1)," +
        "last_reconciled INTEGER NOT NULL," +
        "server_active_until INTEGER NOT NULL DEFAULT 0)");
    SqlStep(qs);

    sqlquery qi = SqlPrepareQueryCampaign(BOOST_DB,
        "INSERT OR IGNORE INTO boost_state(id, last_reconciled, server_active_until)" +
        " VALUES(1, CAST(strftime('%s','now') AS INTEGER), 0)");
    SqlStep(qi);

    sqlquery qp = SqlPrepareQueryCampaign(BOOST_DB,
        "CREATE TABLE IF NOT EXISTS player_boost (" +
        "cdkey TEXT PRIMARY KEY," +
        "personal_active_until INTEGER NOT NULL DEFAULT 0)");
    SqlStep(qp);
}

// ------------------------------------------------------------
// Reconciliation internals

// sum of  remaining_sec of a still-running chain. sCdKey "" = the whole server scope;
// otherwise a single player's personal chain.
int Boost_ChainRemaining(string sScope, string sCdKey)
{
    string sSql = "SELECT COALESCE(SUM(remaining_sec),0) FROM boost_sub" +
        " WHERE scope=@s AND status IN('active','pending')";
    if (sCdKey != "") sSql += " AND cdkey=@k";
    sqlquery q = SqlPrepareQueryCampaign(BOOST_DB, sSql);
    SqlBindString(q, "@s", sScope);
    if (sCdKey != "") SqlBindString(q, "@k", sCdKey);
    return SqlStep(q) ? SqlGetInt(q, 0) : 0;
}

// Drain nBurn seconds off the head(s) of one chain, oldest-first, marking
// exhausted subs 'done'. Then promote the earliest survivor to 'active' and the
// rest to 'pending'. sCdKey "" = server scope; otherwise one player's chain.
void Boost_DrainChain(string sScope, string sCdKey, int nBurn)
{
    string sWhere = "scope=@s AND status IN('active','pending')";
    if (sCdKey != "") sWhere += " AND cdkey=@k";

    int nGuard = 0;
    while (nBurn > 0 && nGuard < 256)
    {
        nGuard++;
        sqlquery qh = SqlPrepareQueryCampaign(BOOST_DB,
            "SELECT id, remaining_sec FROM boost_sub WHERE " + sWhere + " ORDER BY id LIMIT 1");
        SqlBindString(qh, "@s", sScope);
        if (sCdKey != "") SqlBindString(qh, "@k", sCdKey);
        if (!SqlStep(qh)) break;   // chain empty

        int nId  = SqlGetInt(qh, 0);
        int nRem = SqlGetInt(qh, 1);
        int nTake = (nBurn < nRem) ? nBurn : nRem;
        int nNew  = nRem - nTake;
        nBurn -= nTake;

        sqlquery qu = SqlPrepareQueryCampaign(BOOST_DB,
            "UPDATE boost_sub SET remaining_sec=@r, status=@st WHERE id=@id");
        SqlBindInt(qu, "@r", nNew);
        SqlBindString(qu, "@st", (nNew <= 0) ? "done" : "active");
        SqlBindInt(qu, "@id", nId);
        SqlStep(qu);
    }

    // Promote head: exactly one 'active', the rest 'pending'.
    sqlquery qp = SqlPrepareQueryCampaign(BOOST_DB,
        "UPDATE boost_sub SET status='pending' WHERE " + sWhere);
    SqlBindString(qp, "@s", sScope);
    if (sCdKey != "") SqlBindString(qp, "@k", sCdKey);
    SqlStep(qp);

    string sHead = "UPDATE boost_sub SET status='active' WHERE id=" +
        "(SELECT MIN(id) FROM boost_sub WHERE " + sWhere + ")";
    sqlquery qa = SqlPrepareQueryCampaign(BOOST_DB, sHead);
    SqlBindString(qa, "@s", sScope);
    if (sCdKey != "") SqlBindString(qa, "@k", sCdKey);
    SqlStep(qa);
}

// Settle elapsed wall-clock time, promote chain heads, and refresh the cached
// absolute expiry timestamps. Idempotent; safe (and cheap) to call repeatedly.
void Boost_Reconcile()
{
    int nNow = Boost_Now();

    int nLast = nNow;
    sqlquery ql = SqlPrepareQueryCampaign(BOOST_DB,
        "SELECT last_reconciled FROM boost_state WHERE id=1");
    if (SqlStep(ql)) nLast = SqlGetInt(ql, 0);
    int nElapsed = nNow - nLast;
    if (nElapsed < 0) nElapsed = 0;

    // Server chain burns continuously while it has time.
    int nServerRem = Boost_ChainRemaining("server", "");
    int nServerBurn = (nElapsed < nServerRem) ? nElapsed : nServerRem;
    Boost_DrainChain("server", "", nServerBurn);

    // Personal chains only burn during the server-inactive part of the window.
    int nPersInactive = nElapsed - nServerBurn;

    // Snapshot the set of players who have personal subs (before draining, so we
    // still refresh the cache for those whose last sub just expired).
    string sKeys = "";
    sqlquery qk = SqlPrepareQueryCampaign(BOOST_DB,
        "SELECT DISTINCT cdkey FROM boost_sub WHERE scope='personal'");
    while (SqlStep(qk)) sKeys += SqlGetString(qk, 0) + "|";

    int nSrvAfter = Boost_ChainRemaining("server", "");   // = nServerRem - nServerBurn

    int nPos = 0;
    int nBar = FindSubString(sKeys, "|");
    while (nBar >= 0)
    {
        string sKey = GetSubString(sKeys, nPos, nBar - nPos);
        Boost_DrainChain("personal", sKey, nPersInactive);

        int nPersAfter = Boost_ChainRemaining("personal", sKey);
        int nUntil = nNow + nSrvAfter + nPersAfter;
        sqlquery qu = SqlPrepareQueryCampaign(BOOST_DB,
            "INSERT INTO player_boost(cdkey, personal_active_until) VALUES(@k, @u)" +
            " ON CONFLICT(cdkey) DO UPDATE SET personal_active_until=excluded.personal_active_until");
        SqlBindString(qu, "@k", sKey);
        SqlBindInt(qu, "@u", nUntil);
        SqlStep(qu);

        nPos = nBar + 1;
        nBar = FindSubString(sKeys, "|", nPos);
    }

    // Refresh server cache + reconcile marker.
    sqlquery qs = SqlPrepareQueryCampaign(BOOST_DB,
        "UPDATE boost_state SET last_reconciled=@n, server_active_until=@u WHERE id=1");
    SqlBindInt(qs, "@n", nNow);
    SqlBindInt(qs, "@u", nNow + nSrvAfter);
    SqlStep(qs);
}

// ------------------------------------------------------------
// Purchase

// Enqueue a subscription. scope "server" or "personal"; sCdKey is the buyer's CD
// key (also the owner for a personal sub). Reconciles before (so the new row can
// never rewrite the past) and after (to promote heads + refresh caches).
void Boost_Enqueue(string sScope, string sCdKey, string sBuyerName, int nDays)
{
    Boost_Reconcile();

    int nDur = nDays * 86400;
    sqlquery q = SqlPrepareQueryCampaign(BOOST_DB,
        "INSERT INTO boost_sub(scope, cdkey, buyer_name, dur_sec, remaining_sec, status)" +
        " VALUES(@s, @k, @b, @d, @d, 'pending')");
    SqlBindString(q, "@s", sScope);
    SqlBindString(q, "@k", sCdKey);
    SqlBindString(q, "@b", sBuyerName);
    SqlBindInt(q, "@d", nDur);
    SqlStep(q);

    Boost_Reconcile();
}

// ------------------------------------------------------------
// Login report

// Round seconds to a friendly "Nd Nh" string.
string Boost_FmtSpan(int nSec)
{
    if (nSec < 0) nSec = 0;
    int nDays  = nSec / 86400;
    int nHours = (nSec % 86400) / 3600;
    return IntToString(nDays) + "d " + IntToString(nHours) + "h";
}

// Message the entering player about every active + pending 2x subscription
// (server-wide and their own personal), who bought each, and the estimated end
// date of each chain. Silent when nothing is active.
void Boost_LoginReport(object oPC)
{
    Boost_Reconcile();
    int nNow = Boost_Now();

    int nSrvRem = Boost_ChainRemaining("server", "");
    string sMsg = "";

    if (nSrvRem > 0)
    {
        sMsg += "\n[Boost] Server-wide 2x gold & XP is ACTIVE (everyone benefits).";
        sqlquery q = SqlPrepareQueryCampaign(BOOST_DB,
            "SELECT buyer_name, remaining_sec, status FROM boost_sub" +
            " WHERE scope='server' AND status IN('active','pending') ORDER BY id");
        while (SqlStep(q))
        {
            string sTag = (SqlGetString(q, 2) == "active") ? "active" : "queued";
            sMsg += "\n   - " + SqlGetString(q, 0) + " (" + sTag + ", "
                 + Boost_FmtSpan(SqlGetInt(q, 1)) + ")";
        }
        sMsg += "\n   Chain ends ~" + Boost_FmtDate(nNow + nSrvRem) + ".";
    }

    string sKey = GetPCPublicCDKey(oPC);
    int nPersRem = Boost_ChainRemaining("personal", sKey);
    if (nPersRem > 0)
    {
        if (nSrvRem > 0)
            sMsg += "\n[Boost] Your personal 2x is PAUSED while the server buff runs; "
                 + Boost_FmtSpan(nPersRem) + " of personal time is preserved.";
        else
            sMsg += "\n[Boost] Your personal 2x gold & XP is ACTIVE ("
                 + Boost_FmtSpan(nPersRem) + " remaining).";
        // personal_active_until already folds in the server-pause offset.
        sMsg += "\n   Your boost ends ~" + Boost_FmtDate(nNow + nSrvRem + nPersRem) + ".";
    }

    if (sMsg != "") SendMessageToPC(oPC, sMsg);
}
