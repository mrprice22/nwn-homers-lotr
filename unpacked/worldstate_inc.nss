// worldstate_inc.nss - Shared server-wide world-state helpers
//
// Campaign DB: "worldstatedb" (SQLite, file database/worldstatedb.sqlite3 on the
// server - never part of the .mod). A simple server-wide key -> value store for
// PERSISTENT GLOBAL state that many players read and affect and that changes over
// time: contested-territory control, siege-engine progress, timed world buffs,
// weekly resource claims, etc.
//
// This is the SERVER-WIDE counterpart to quest_cd_inc.nss: quest_cd_inc keys off
// GetObjectUUID (one row per character); world-state keys off a plain string key
// (one row for the whole server). Use quest_cd_inc for "has THIS player done X",
// use worldstate_inc for "what is the current state of the WORLD".
//
// Time is real wall-clock (SQLite strftime('%s','now')), NOT the game calendar,
// so decay/weekly behavior survives reboots, relogs and module time changes -
// exactly like quest_cd_inc.nss.
//
// ------------------------------------------------------------
// Schema (two tables, both created idempotently by WS_InitDb):
//
//   world_state(skey PK, ival, sval, updated_at)
//       The value store. ival = the primary integer global; sval = an optional
//       string (e.g. a weekly-claim owner's public CD key or char name).
//
//   world_state_rule(skey PK, kind, rate, target, period, last_tick)
//       Optional per-key time behavior, applied by WS_Tick() off the heartbeat:
//         kind='decay'  - every `period` real seconds, move ival toward `target`
//                         by `rate` (multi-step catch-up after a reboot gap).
//         kind='weekly' - reset ival -> `target` at each ISO-week rollover
//                         (strftime('%Y-%W'), UTC), independent of `rate`/`period`.
//         kind='none'   - inert (same as having no rule row).
//
// ------------------------------------------------------------
// Usage - a decaying siege / tug-of-war meter:
//
//   // At quest/system init (once - e.g. in an OnModuleLoad ExecuteScript, or the
//   // first time the contested area loads): bleed 1 point/minute back toward 0.
//   #include "worldstate_inc"
//   WS_RegisterDecay("isengard_warmachine", 1, 0);   // rate=1, target=0, per-minute
//
//   // Players pushing the meter (clamped to 0..100):
//   WS_AdjustInt("isengard_warmachine", +5, 0, 100);   // orcs gain ground
//   WS_AdjustInt("isengard_warmachine", -5, 0, 100);   // ents push back
//
//   // Anywhere that needs the current value (StartingConditional, spawn script):
//   if (WS_GetInt("isengard_warmachine") >= 100) { /* Isengard wins this cycle */ }
//
// Usage - a weekly resource claim (mithril seam), with an owner string:
//
//   WS_RegisterWeekly("mithril_seam", 0);              // ival resets to 0 each week
//   ...
//   // On a successful weekly claim:
//   WS_SetInt("mithril_seam", 1);                      // claimed this week
//   WS_SetStr("mithril_seam", GetPCPublicCDKey(oPC));  // remember who
//   // Gate the reward:
//   if (WS_GetInt("mithril_seam") == 0) { /* still available this week */ }
//
// Usage - a timed world buff (goblin-town throne, 7 real days):
//
//   WS_RegisterDecay("goblin_throne", 1, 0, 604800);   // one step, target 0, 7d period
//   WS_SetInt("goblin_throne", 1);                      // buff on; WS_Tick clears it after 7d
//   if (WS_GetInt("goblin_throne") > 0) { /* orc spawns buffed */ }
//
// WS_InitDb() is called from onmoduleload.nss; WS_Tick() is called (throttled to
// ~1/min) from the module heartbeat (bleeding.nss). New consumers need no setup
// beyond the #include and a one-time WS_Register* call.

const string WS_DB   = "worldstatedb";

// Global heartbeat throttle: WS_Tick() does real work at most once per this many
// real seconds, so it is safe to call on every 6s heartbeat pulse.
const int    WS_TICK_INTERVAL = 60;

// Reserved key holding the last time WS_Tick() actually ran its rule pass.
const string WS_TICK_KEY = "__ws_last_tick";

// ------------------------------------------------------------
// Schema - idempotent; called once from onmoduleload.nss.

void WS_InitDb()
{
    sqlquery q = SqlPrepareQueryCampaign(WS_DB,
        "CREATE TABLE IF NOT EXISTS world_state (" +
        "skey TEXT PRIMARY KEY," +
        "ival INTEGER NOT NULL DEFAULT 0," +
        "sval TEXT," +
        "updated_at INTEGER NOT NULL DEFAULT 0)");
    SqlStep(q);

    sqlquery r = SqlPrepareQueryCampaign(WS_DB,
        "CREATE TABLE IF NOT EXISTS world_state_rule (" +
        "skey TEXT PRIMARY KEY," +
        "kind TEXT NOT NULL DEFAULT 'none'," +   // 'decay' | 'weekly' | 'none'
        "rate INTEGER NOT NULL DEFAULT 0," +     // decay: units per period
        "target INTEGER NOT NULL DEFAULT 0," +   // decay/weekly destination value
        "period INTEGER NOT NULL DEFAULT 0," +   // decay: real seconds per step
        "last_tick INTEGER NOT NULL DEFAULT 0)");
    SqlStep(r);
}

// ------------------------------------------------------------
// Small helpers

// Real-world "now" as unix-epoch seconds (from SQLite, not the game clock).
int WS_Now()
{
    sqlquery q = SqlPrepareQueryCampaign(WS_DB,
        "SELECT CAST(strftime('%s','now') AS INTEGER)");
    return SqlStep(q) ? SqlGetInt(q, 0) : 0;
}

// ------------------------------------------------------------
// Int value store. Readers default gracefully when the key is absent.

// Current integer value of sKey, or nDefault when no row exists yet.
int WS_GetInt(string sKey, int nDefault = 0)
{
    sqlquery q = SqlPrepareQueryCampaign(WS_DB,
        "SELECT ival FROM world_state WHERE skey=@k");
    SqlBindString(q, "@k", sKey);
    if (!SqlStep(q)) return nDefault;
    return SqlGetInt(q, 0);
}

// Set sKey's integer value (UPSERT; preserves any existing sval).
void WS_SetInt(string sKey, int nVal)
{
    sqlquery q = SqlPrepareQueryCampaign(WS_DB,
        "INSERT INTO world_state(skey,ival,updated_at)" +
        " VALUES(@k,@v,CAST(strftime('%s','now') AS INTEGER))" +
        " ON CONFLICT(skey) DO UPDATE SET" +
        " ival=excluded.ival, updated_at=excluded.updated_at");
    SqlBindString(q, "@k", sKey);
    SqlBindInt(q,    "@v", nVal);
    SqlStep(q);
}

// Move sKey's value by nDelta and persist. Clamps to [nMin,nMax] ONLY when
// nMin != nMax (pass both 0 - the default - for an unclamped counter).
// Returns the new stored value.
int WS_AdjustInt(string sKey, int nDelta, int nMin = 0, int nMax = 0)
{
    int nNew = WS_GetInt(sKey) + nDelta;
    if (nMin != nMax)
    {
        if (nNew < nMin) nNew = nMin;
        if (nNew > nMax) nNew = nMax;
    }
    WS_SetInt(sKey, nNew);
    return nNew;
}

// ------------------------------------------------------------
// String value store (e.g. a weekly-claim owner's CD key). Same row as the int.

// Current string value of sKey, or sDefault when no row / NULL sval.
string WS_GetStr(string sKey, string sDefault = "")
{
    sqlquery q = SqlPrepareQueryCampaign(WS_DB,
        "SELECT sval FROM world_state WHERE skey=@k AND sval IS NOT NULL");
    SqlBindString(q, "@k", sKey);
    if (!SqlStep(q)) return sDefault;
    return SqlGetString(q, 0);
}

// Set sKey's string value (UPSERT; preserves any existing ival).
void WS_SetStr(string sKey, string sVal)
{
    sqlquery q = SqlPrepareQueryCampaign(WS_DB,
        "INSERT INTO world_state(skey,sval,updated_at)" +
        " VALUES(@k,@v,CAST(strftime('%s','now') AS INTEGER))" +
        " ON CONFLICT(skey) DO UPDATE SET" +
        " sval=excluded.sval, updated_at=excluded.updated_at");
    SqlBindString(q, "@k", sKey);
    SqlBindString(q, "@v", sVal);
    SqlStep(q);
}

// ------------------------------------------------------------
// Rule registry - idempotent upserts. Register once; WS_Tick applies them.

// Bleed sKey toward nTarget by nRatePerStep every nPeriodSec real seconds.
// Default period is the heartbeat tick interval (per-minute decay).
void WS_RegisterDecay(string sKey, int nRatePerStep, int nTarget, int nPeriodSec = WS_TICK_INTERVAL)
{
    if (nPeriodSec < 1) nPeriodSec = WS_TICK_INTERVAL;
    sqlquery q = SqlPrepareQueryCampaign(WS_DB,
        "INSERT INTO world_state_rule(skey,kind,rate,target,period,last_tick)" +
        " VALUES(@k,'decay',@r,@t,@p,CAST(strftime('%s','now') AS INTEGER))" +
        " ON CONFLICT(skey) DO UPDATE SET" +
        " kind='decay', rate=excluded.rate, target=excluded.target," +
        " period=excluded.period, last_tick=excluded.last_tick");
    SqlBindString(q, "@k", sKey);
    SqlBindInt(q,    "@r", nRatePerStep);
    SqlBindInt(q,    "@t", nTarget);
    SqlBindInt(q,    "@p", nPeriodSec);
    SqlStep(q);
}

// Reset sKey's ival to nResetTo at each ISO-week rollover (UTC, %Y-%W).
void WS_RegisterWeekly(string sKey, int nResetTo)
{
    sqlquery q = SqlPrepareQueryCampaign(WS_DB,
        "INSERT INTO world_state_rule(skey,kind,rate,target,period,last_tick)" +
        " VALUES(@k,'weekly',0,@t,0,CAST(strftime('%s','now') AS INTEGER))" +
        " ON CONFLICT(skey) DO UPDATE SET" +
        " kind='weekly', rate=0, target=excluded.target, period=0," +
        " last_tick=excluded.last_tick");
    SqlBindString(q, "@k", sKey);
    SqlBindInt(q,    "@t", nResetTo);
    SqlStep(q);
}

// Remove any time rule for sKey (the value row is left untouched).
void WS_ClearRule(string sKey)
{
    sqlquery q = SqlPrepareQueryCampaign(WS_DB,
        "DELETE FROM world_state_rule WHERE skey=@k");
    SqlBindString(q, "@k", sKey);
    SqlStep(q);
}

// ------------------------------------------------------------
// Tick - apply one rule row. Reads its own value, computes, writes back.

void WS_ApplyRule(string sKey)
{
    sqlquery q = SqlPrepareQueryCampaign(WS_DB,
        "SELECT kind,rate,target,period,last_tick FROM world_state_rule WHERE skey=@k");
    SqlBindString(q, "@k", sKey);
    if (!SqlStep(q)) return;

    string sKind    = SqlGetString(q, 0);
    int    nRate    = SqlGetInt(q, 1);
    int    nTarget  = SqlGetInt(q, 2);
    int    nPeriod  = SqlGetInt(q, 3);
    int    nLast    = SqlGetInt(q, 4);
    int    nNow     = WS_Now();

    if (sKind == "decay")
    {
        if (nPeriod < 1 || nRate <= 0) return;
        int nSteps = (nNow - nLast) / nPeriod;
        if (nSteps <= 0) return;

        int nVal   = WS_GetInt(sKey);
        int nMove  = nRate * nSteps;
        if (nVal > nTarget)
        {
            nVal -= nMove;
            if (nVal < nTarget) nVal = nTarget;
        }
        else if (nVal < nTarget)
        {
            nVal += nMove;
            if (nVal > nTarget) nVal = nTarget;
        }
        WS_SetInt(sKey, nVal);

        // Advance last_tick by whole steps consumed (keeps the phase; a reboot
        // gap is caught up in one multi-step move above).
        sqlquery u = SqlPrepareQueryCampaign(WS_DB,
            "UPDATE world_state_rule SET last_tick=last_tick+@d WHERE skey=@k");
        SqlBindInt(u,    "@d", nSteps * nPeriod);
        SqlBindString(u, "@k", sKey);
        SqlStep(u);
    }
    else if (sKind == "weekly")
    {
        // Reset when the stored last_tick falls in an earlier ISO week than now.
        sqlquery w = SqlPrepareQueryCampaign(WS_DB,
            "SELECT strftime('%Y-%W',@l,'unixepoch') <> strftime('%Y-%W','now')");
        SqlBindInt(w, "@l", nLast);
        int bRoll = SqlStep(w) ? SqlGetInt(w, 0) : 0;
        if (!bRoll) return;

        WS_SetInt(sKey, nTarget);
        sqlquery u = SqlPrepareQueryCampaign(WS_DB,
            "UPDATE world_state_rule SET last_tick=CAST(strftime('%s','now') AS INTEGER)" +
            " WHERE skey=@k");
        SqlBindString(u, "@k", sKey);
        SqlStep(u);
    }
}

// Heartbeat entry point. Self-throttles to once per WS_TICK_INTERVAL real
// seconds, then applies every registered rule. Cheap and safe to call every 6s
// heartbeat pulse - the throttle check is a single indexed lookup.
void WS_Tick()
{
    int nNow  = WS_Now();
    int nLast = WS_GetInt(WS_TICK_KEY, 0);
    if (nLast != 0 && (nNow - nLast) < WS_TICK_INTERVAL) return;
    WS_SetInt(WS_TICK_KEY, nNow);

    // Collect the rule keys first, then apply - don't mutate rows mid-SELECT.
    string sKeys = "";
    sqlquery q = SqlPrepareQueryCampaign(WS_DB,
        "SELECT skey FROM world_state_rule WHERE kind IN ('decay','weekly')");
    while (SqlStep(q))
        sKeys += SqlGetString(q, 0) + "\n";

    int nStart = 0;
    int nNL = FindSubString(sKeys, "\n", nStart);
    while (nNL >= 0)
    {
        string sKey = GetSubString(sKeys, nStart, nNL - nStart);
        if (sKey != "") WS_ApplyRule(sKey);
        nStart = nNL + 1;
        nNL = FindSubString(sKeys, "\n", nStart);
    }
}

// ------------------------------------------------------------
// Admin / testing

// Forget a key entirely (value row + any rule). DM reset / UAT helper.
void WS_Clear(string sKey)
{
    sqlquery q = SqlPrepareQueryCampaign(WS_DB,
        "DELETE FROM world_state WHERE skey=@k");
    SqlBindString(q, "@k", sKey);
    SqlStep(q);
    WS_ClearRule(sKey);
}
