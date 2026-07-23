// faction_db.nss — Good/Evil allegiance persistence helpers
//
// Campaign DB: "factiondb" (SQLite, file database/factiondb.sqlite3 on the
// server — never part of the .mod). One row per character recording which
// side of the module's 2-faction Good-vs-Evil allegiance model that character
// has taken, so it survives relog/reboot and is re-applied on login.
//
// This is NOT tied to GetAlignment — allegiance is faction reputation only
// (AdjustReputation against the invisible anchor NPCs), so a True-Neutral
// druid can still be Good- or Evil-aligned by faction. The enemy side is
// hostile on sight (the -100 AdjustReputation drops the opposing anchor below
// the attack threshold), exactly as the legacy adjuster scripts did.
//
// Schema:  faction_standing(uuid PK, cdkey, char_name, allegiance, standing,
//                           updated_at)
//          Character identity is GetObjectUUID (persists in the .bic, same key
//          the bestiary / quest cooldowns use); cdkey/char_name are stored for
//          out-of-band inspection with sqlite3 only — lookups never use them.
//          allegiance ∈ {'Good','Evil','Neutral'}; standing is 0-1000 and can
//          be grown by faction quests (Faction_AdjustStanding) to gate rewards.
//
// Live reputation is driven entirely off the stored row by Faction_ApplyLive —
// the single source of truth. Both Faction_SetAllegiance (the placeable/dialog
// adjusters) and the OnClientEnter login hook call it, so the wire never
// diverges from the DB. Anchor NPCs (invisible objects) are tagged:
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

// ------------------------------------------------------------
// Schema — idempotent; called once from onmoduleload.nss.

void Faction_InitDb()
{
    sqlquery q = SqlPrepareQueryCampaign(FACTION_DB,
        "CREATE TABLE IF NOT EXISTS faction_standing (" +
        "uuid TEXT PRIMARY KEY," +
        "cdkey TEXT," +
        "char_name TEXT," +
        "allegiance TEXT NOT NULL DEFAULT 'Neutral'," +
        "standing INTEGER NOT NULL DEFAULT 0," +
        "updated_at INTEGER NOT NULL DEFAULT 0)");
    SqlStep(q);
}

// ------------------------------------------------------------
// SELECT-only readers.

// The character's stored allegiance ('Good'/'Evil'/'Neutral'); 'Neutral' when
// no row exists yet.
string Faction_GetAllegiance(object oPC)
{
    sqlquery q = SqlPrepareQueryCampaign(FACTION_DB,
        "SELECT allegiance FROM faction_standing WHERE uuid=@u");
    SqlBindString(q, "@u", GetObjectUUID(oPC));
    if (!SqlStep(q)) return "Neutral";
    return SqlGetString(q, 0);
}

// The character's stored standing (0-1000); 0 when no row exists yet.
int Faction_GetStanding(object oPC)
{
    sqlquery q = SqlPrepareQueryCampaign(FACTION_DB,
        "SELECT standing FROM faction_standing WHERE uuid=@u");
    SqlBindString(q, "@u", GetObjectUUID(oPC));
    if (!SqlStep(q)) return 0;
    return SqlGetInt(q, 0);
}

// ------------------------------------------------------------
// Live reputation — the single source of truth. Reads the stored row and
// AdjustReputation()s the PC against the anchor NPCs to match. Values are
// deltas that the engine clamps to [0,100], so re-applying on every login is
// idempotent (max toward the chosen side, floor the others). No row -> no
// change (leave the engine's neutral defaults). Uses the real anchor tag
// casing: capital 'Goodfaction' / 'Evilfaction' / 'Neutralfaction'.
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

// Record the character's allegiance (UPSERT) AND apply it live immediately.
// Called by the Good/Evil adjuster placeables (and the factaduster dialog).
void Faction_SetAllegiance(object oPC, string sAllegiance, int nStanding=1000)
{
    if (nStanding < 0)    nStanding = 0;
    if (nStanding > 1000) nStanding = 1000;

    sqlquery q = SqlPrepareQueryCampaign(FACTION_DB,
        "INSERT INTO faction_standing(uuid,cdkey,char_name,allegiance,standing,updated_at)" +
        " VALUES(@u,@k,@n,@a,@s,CAST(strftime('%s','now') AS INTEGER))" +
        " ON CONFLICT(uuid) DO UPDATE SET" +
        " allegiance=excluded.allegiance," +
        " standing=excluded.standing," +
        " cdkey=excluded.cdkey," +
        " char_name=excluded.char_name," +
        " updated_at=excluded.updated_at");
    SqlBindString(q, "@u", GetObjectUUID(oPC));
    SqlBindString(q, "@k", GetPCPublicCDKey(oPC));
    SqlBindString(q, "@n", GetName(oPC));
    SqlBindString(q, "@a", sAllegiance);
    SqlBindInt(q,    "@s", nStanding);
    SqlStep(q);

    Faction_ApplyLive(oPC);
}

// Move the character's standing by nDelta (clamped 0-1000), preserving the
// current allegiance, and persist the result. For faction quests to grow/burn
// standing (later gating quest rewards). Creates a Neutral row if none exists.
void Faction_AdjustStanding(object oPC, int nDelta)
{
    int nNew = Faction_GetStanding(oPC) + nDelta;
    if (nNew < 0)    nNew = 0;
    if (nNew > 1000) nNew = 1000;
    Faction_SetAllegiance(oPC, Faction_GetAllegiance(oPC), nNew);
}
