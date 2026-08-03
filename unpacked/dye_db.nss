// dye_db.nss - persistence for the Dye Studio "save/apply color scheme" feature.
//
// One saved scheme PER CHARACTER, keyed by (account CD-key, character GUID), so a
// player can copy an item's six armor-tint channel colors and paste them onto
// another item - and it survives reboots. Saving again overwrites the scheme.
// Uses the campaign SQLite DB "dyedb" (mirrors tele_db.nss / merit_db.nss).

const string DYE_DB = "dyedb";

// Idempotent - safe to call on every window open.
void Dye_InitDb()
{
    sqlquery q = SqlPrepareQueryCampaign(DYE_DB,
        "CREATE TABLE IF NOT EXISTS dye_scheme (" +
        "cdkey TEXT NOT NULL, pid TEXT NOT NULL," +
        "c0 INTEGER, c1 INTEGER, c2 INTEGER, c3 INTEGER, c4 INTEGER, c5 INTEGER," +
        "PRIMARY KEY(cdkey, pid))");
    SqlStep(q);
}

// Upsert this character's saved scheme (6 armor-color channel values).
void Dye_SaveScheme(object oPC, int c0, int c1, int c2, int c3, int c4, int c5)
{
    sqlquery q = SqlPrepareQueryCampaign(DYE_DB,
        "INSERT INTO dye_scheme(cdkey, pid, c0, c1, c2, c3, c4, c5)" +
        " VALUES(@k, @p, @c0, @c1, @c2, @c3, @c4, @c5)" +
        " ON CONFLICT(cdkey, pid) DO UPDATE SET" +
        " c0=excluded.c0, c1=excluded.c1, c2=excluded.c2," +
        " c3=excluded.c3, c4=excluded.c4, c5=excluded.c5");
    SqlBindString(q, "@k", GetPCPublicCDKey(oPC));
    SqlBindString(q, "@p", GetObjectUUID(oPC));
    SqlBindInt(q, "@c0", c0);
    SqlBindInt(q, "@c1", c1);
    SqlBindInt(q, "@c2", c2);
    SqlBindInt(q, "@c3", c3);
    SqlBindInt(q, "@c4", c4);
    SqlBindInt(q, "@c5", c5);
    SqlStep(q);
}

// Load this character's scheme into PC locals DYE_LS_0..5. Returns TRUE if a
// scheme exists, FALSE otherwise.
int Dye_LoadScheme(object oPC)
{
    sqlquery q = SqlPrepareQueryCampaign(DYE_DB,
        "SELECT c0, c1, c2, c3, c4, c5 FROM dye_scheme WHERE cdkey=@k AND pid=@p LIMIT 1");
    SqlBindString(q, "@k", GetPCPublicCDKey(oPC));
    SqlBindString(q, "@p", GetObjectUUID(oPC));
    if (!SqlStep(q)) return FALSE;
    int i;
    for (i = 0; i < 6; i++)
        SetLocalInt(oPC, "DYE_LS_" + IntToString(i), SqlGetInt(q, i));
    return TRUE;
}
