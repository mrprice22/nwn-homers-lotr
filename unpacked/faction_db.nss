// faction_db.nss — Good/Evil allegiance + dual-faction standing persistence
//
// Campaign DB: "factiondb" (SQLite, file database/factiondb.sqlite3 on the
// server — never part of the .mod). One row per character.
//
// The module runs a 2-faction Good-vs-Evil model. Three distinct things are
// tracked per character, and they are deliberately independent:
//
//   * allegiance  — the character's CURRENT live side ('Good'/'Evil'/'Neutral').
//                   This is what Faction_ApplyLive turns into live reputation
//                   (who is hostile). Players switch it FREELY at the Well of
//                   Eru light-shafts (goodadjuster / eiladjust) — unless an oath
//                   locks them (below).
//   * good_standing / evil_standing — PROGRESS with each faction (0-1000 each),
//                   tracked INDEPENDENTLY so playing both sides is not punished.
//                   Faction quests grow the relevant side via
//                   Faction_AdjustStanding, which also applies a small reversible
//                   "loyalty bleed" (FACTION_BLEED_PCT) to the opposite side —
//                   floored at 0, never a full reset. Consistent one-faction play
//                   simply pulls ahead.
//   * oath        — '' | 'Good' | 'Evil'. An OPTIONAL class oath (Paladin's Oath
//                   of the West -> 'Good'; Blackguard's Black Oath -> 'Evil';
//                   possibly others later). Once sworn it LOCKS the character out
//                   of the opposite side's light-shaft (Faction_CanSwitchTo), and
//                   Faction_SetOath commits their allegiance to that side.
//
// Allegiance is NOT tied to GetAlignment — it is faction reputation only
// (AdjustReputation against the invisible anchor NPCs), so a True-Neutral druid
// can still be Good- or Evil-aligned by faction. The enemy side is hostile on
// sight (the -100 AdjustReputation drops the opposing anchor below the attack
// threshold), exactly as the legacy adjuster scripts did.
//
// Schema:  faction_standing(uuid PK, cdkey, char_name, allegiance,
//                           good_standing, evil_standing, oath,
//                           standing (legacy, unused), updated_at)
//          Character identity is GetObjectUUID (persists in the .bic, same key
//          the bestiary / quest cooldowns use); cdkey/char_name are stored for
//          out-of-band inspection with sqlite3 only — lookups never use them.
//
// Live reputation is driven entirely off the stored allegiance by
// Faction_ApplyLive — the single source of truth. Both Faction_SetAllegiance
// (the placeable/dialog adjusters) and the OnClientEnter login hook call it, so
// the wire never diverges from the DB. Anchor NPCs (invisible objects) are tagged:
//     Goodfaction  (invisobj001)   — the Free Peoples of Middle Earth
//     Evilfaction  (invisobj002)   — Sauron / Mordor
//     Neutralfaction               — (optional; not placed at time of writing —
//                                    the -100 against it simply no-ops)
// GetObjectByTag on a missing anchor returns OBJECT_INVALID and AdjustReputation
// no-ops, so a missing Neutralfaction anchor is harmless.
//
// Faction_InitDb() is called from onmoduleload.nss — new consumers need no
// setup beyond the #include.

const string FACTION_DB = "factiondb";

// Loyalty bleed: completing an opposite-faction action reduces your other side's
// standing by this percentage of the gain (floored at 0, never a full reset).
const int    FACTION_BLEED_PCT = 25;

// ------------------------------------------------------------
// Schema — idempotent; called once from onmoduleload.nss. Also migrates an
// older factiondb (single 'standing' column, no dual/oath columns) forward in
// place: CREATE IF NOT EXISTS covers fresh DBs, then ADD COLUMN each missing
// column (guarded by a PRAGMA check so re-running never errors), then seed the
// per-side columns from the legacy single value on first migration.

// Does faction_standing already have a column named sCol?
int Faction_HasColumn(string sCol)
{
    sqlquery q = SqlPrepareQueryCampaign(FACTION_DB,
        "SELECT COUNT(*) FROM pragma_table_info('faction_standing') WHERE name=@c");
    SqlBindString(q, "@c", sCol);
    if (!SqlStep(q)) return FALSE;
    return SqlGetInt(q, 0) > 0;
}

void Faction_AddColumn(string sCol, string sDef)
{
    if (Faction_HasColumn(sCol)) return;
    // Column names/defs are compile-time literals here, never user input.
    SqlStep(SqlPrepareQueryCampaign(FACTION_DB,
        "ALTER TABLE faction_standing ADD COLUMN " + sCol + " " + sDef));
}

void Faction_InitDb()
{
    // Fresh DBs: full current schema.
    sqlquery q = SqlPrepareQueryCampaign(FACTION_DB,
        "CREATE TABLE IF NOT EXISTS faction_standing (" +
        "uuid TEXT PRIMARY KEY," +
        "cdkey TEXT," +
        "char_name TEXT," +
        "allegiance TEXT NOT NULL DEFAULT 'Neutral'," +
        "good_standing INTEGER NOT NULL DEFAULT 0," +
        "evil_standing INTEGER NOT NULL DEFAULT 0," +
        "oath TEXT NOT NULL DEFAULT ''," +
        "standing INTEGER NOT NULL DEFAULT 0," +   // legacy, unused
        "updated_at INTEGER NOT NULL DEFAULT 0)");
    SqlStep(q);

    // Older DBs shipped this session had only: allegiance, standing, updated_at.
    // Add the new columns in place (each guarded), then seed once.
    int bNeedSeed = !Faction_HasColumn("good_standing"); // true only pre-migration
    Faction_AddColumn("good_standing", "INTEGER NOT NULL DEFAULT 0");
    Faction_AddColumn("evil_standing", "INTEGER NOT NULL DEFAULT 0");
    Faction_AddColumn("oath",          "TEXT NOT NULL DEFAULT ''");

    if (bNeedSeed && Faction_HasColumn("standing"))
    {
        // Carry any legacy single standing into the side that matches allegiance.
        SqlStep(SqlPrepareQueryCampaign(FACTION_DB,
            "UPDATE faction_standing SET good_standing=standing " +
            "WHERE allegiance='Good' AND standing>0"));
        SqlStep(SqlPrepareQueryCampaign(FACTION_DB,
            "UPDATE faction_standing SET evil_standing=standing " +
            "WHERE allegiance='Evil' AND standing>0"));
    }
}

// ------------------------------------------------------------
// Ensure a row exists for oPC (Neutral / 0 / no-oath) so UPDATEs land.
void Faction_EnsureRow(object oPC)
{
    sqlquery q = SqlPrepareQueryCampaign(FACTION_DB,
        "INSERT OR IGNORE INTO faction_standing" +
        "(uuid,cdkey,char_name,allegiance,good_standing,evil_standing,oath,updated_at)" +
        " VALUES(@u,@k,@n,'Neutral',0,0,'',CAST(strftime('%s','now') AS INTEGER))");
    SqlBindString(q, "@u", GetObjectUUID(oPC));
    SqlBindString(q, "@k", GetPCPublicCDKey(oPC));
    SqlBindString(q, "@n", GetName(oPC));
    SqlStep(q);
}

// ------------------------------------------------------------
// SELECT-only readers.

// The character's stored live allegiance ('Good'/'Evil'/'Neutral'); 'Neutral'
// when no row exists yet.
string Faction_GetAllegiance(object oPC)
{
    sqlquery q = SqlPrepareQueryCampaign(FACTION_DB,
        "SELECT allegiance FROM faction_standing WHERE uuid=@u");
    SqlBindString(q, "@u", GetObjectUUID(oPC));
    if (!SqlStep(q)) return "Neutral";
    return SqlGetString(q, 0);
}

// Standing (0-1000) with one side; sSide is "Good" or "Evil". 0 when absent.
int Faction_GetStanding(object oPC, string sSide)
{
    string sCol = (sSide == "Evil") ? "evil_standing" : "good_standing";
    sqlquery q = SqlPrepareQueryCampaign(FACTION_DB,
        "SELECT " + sCol + " FROM faction_standing WHERE uuid=@u");
    SqlBindString(q, "@u", GetObjectUUID(oPC));
    if (!SqlStep(q)) return 0;
    return SqlGetInt(q, 0);
}

// The character's sworn oath side ('Good'/'Evil'), or "" if none.
string Faction_GetOath(object oPC)
{
    sqlquery q = SqlPrepareQueryCampaign(FACTION_DB,
        "SELECT oath FROM faction_standing WHERE uuid=@u");
    SqlBindString(q, "@u", GetObjectUUID(oPC));
    if (!SqlStep(q)) return "";
    return SqlGetString(q, 0);
}

// May oPC switch their live allegiance to sSide? FALSE only when an oath binds
// them to the opposite side. (Switching to your own oath side, or Neutral, is
// never blocked here — callers decide whether Neutral is offered.)
int Faction_CanSwitchTo(object oPC, string sSide)
{
    string sOath = Faction_GetOath(oPC);
    if (sOath == "" ) return TRUE;
    if (sOath == "Good" && sSide == "Evil") return FALSE;
    if (sOath == "Evil" && sSide == "Good") return FALSE;
    return TRUE;
}

// ------------------------------------------------------------
// Live reputation — the single source of truth. Reads the stored allegiance and
// AdjustReputation()s the PC against the anchor NPCs to match. Values are deltas
// that the engine clamps to [0,100], so re-applying on every login is idempotent
// (max toward the chosen side, floor the others). No row -> no change (leave the
// engine's neutral defaults). Uses the real anchor tag casing: capital
// 'Goodfaction' / 'Evilfaction' / 'Neutralfaction'.
void Faction_ApplyLive(object oPC)
{
    sqlquery q = SqlPrepareQueryCampaign(FACTION_DB,
        "SELECT allegiance FROM faction_standing WHERE uuid=@u");
    SqlBindString(q, "@u", GetObjectUUID(oPC));
    if (!SqlStep(q)) return;
    string sAll = SqlGetString(q, 0);

    object oGood = GetObjectByTag("Goodfaction");
    object oEvil = GetObjectByTag("Evilfaction");
    object oNeut = GetObjectByTag("Neutralfaction");

    if (sAll == "Good")
    {
        AdjustReputation(oPC, oGood, 1000);
        AdjustReputation(oPC, oEvil, -100);
        AdjustReputation(oPC, oNeut, -100);
    }
    else if (sAll == "Evil")
    {
        AdjustReputation(oPC, oEvil, 1000);
        AdjustReputation(oPC, oGood, -100);
        AdjustReputation(oPC, oNeut, -100);
    }
    // 'Neutral' -> no reputation change (engine defaults are neutral).
}

// ------------------------------------------------------------
// Writers.

// Set the character's live allegiance ('Good'/'Evil'/'Neutral') AND apply it
// live immediately. Called by the Good/Evil adjuster placeables (and the
// factaduster dialog). Standing columns are untouched — allegiance is the live
// side, standing is durable progress. NOTE: this does NOT enforce the oath lock;
// callers gate with Faction_CanSwitchTo() so they can show a fitting message.
void Faction_SetAllegiance(object oPC, string sAllegiance)
{
    Faction_EnsureRow(oPC);
    sqlquery q = SqlPrepareQueryCampaign(FACTION_DB,
        "UPDATE faction_standing SET allegiance=@a," +
        " updated_at=CAST(strftime('%s','now') AS INTEGER) WHERE uuid=@u");
    SqlBindString(q, "@a", sAllegiance);
    SqlBindString(q, "@u", GetObjectUUID(oPC));
    SqlStep(q);

    Faction_ApplyLive(oPC);
}

// Move the character's standing with one side by nDelta (clamped 0-1000), and —
// when growing (nDelta>0) and bBleed — apply a small reversible loyalty bleed of
// FACTION_BLEED_PCT of the gain to the OPPOSITE side (floored at 0, never a full
// reset). For faction quests to grow/burn standing (later gating rewards).
// Does not touch allegiance. Creates a Neutral row if none exists.
void Faction_AdjustStanding(object oPC, string sSide, int nDelta, int bBleed=TRUE)
{
    Faction_EnsureRow(oPC);

    string sMine = (sSide == "Evil") ? "evil_standing" : "good_standing";
    string sOpp  = (sSide == "Evil") ? "good_standing" : "evil_standing";

    int nMine = Faction_GetStanding(oPC, sSide) + nDelta;
    if (nMine < 0)    nMine = 0;
    if (nMine > 1000) nMine = 1000;

    string sOppSide = (sSide == "Evil") ? "Good" : "Evil";
    int nOpp = Faction_GetStanding(oPC, sOppSide);
    if (bBleed && nDelta > 0)
    {
        nOpp -= (nDelta * FACTION_BLEED_PCT) / 100;
        if (nOpp < 0) nOpp = 0;
    }

    sqlquery q = SqlPrepareQueryCampaign(FACTION_DB,
        "UPDATE faction_standing SET " + sMine + "=@m," + sOpp + "=@o," +
        " updated_at=CAST(strftime('%s','now') AS INTEGER) WHERE uuid=@u");
    SqlBindInt(q,    "@m", nMine);
    SqlBindInt(q,    "@o", nOpp);
    SqlBindString(q, "@u", GetObjectUUID(oPC));
    SqlStep(q);
}

// Swear an optional class oath to sSide ('Good'/'Evil'). Records the oath (which
// locks the character out of the opposite light-shaft via Faction_CanSwitchTo)
// AND commits their live allegiance to that side. One-way by design; callers are
// the one-time, non-farmable oath rites (Paladin PLD_TakeOath, Blackguard fall).
void Faction_SetOath(object oPC, string sSide)
{
    Faction_EnsureRow(oPC);
    sqlquery q = SqlPrepareQueryCampaign(FACTION_DB,
        "UPDATE faction_standing SET oath=@o, allegiance=@o," +
        " updated_at=CAST(strftime('%s','now') AS INTEGER) WHERE uuid=@u");
    SqlBindString(q, "@o", sSide);
    SqlBindString(q, "@u", GetObjectUUID(oPC));
    SqlStep(q);

    Faction_ApplyLive(oPC);
}
