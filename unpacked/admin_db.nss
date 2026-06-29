// admin_db.nss — Admin whitelist database helpers
//
// Campaign DB: "admindb" (SQLite, lives in the server's database/ folder on the
// physical machine — never part of the .mod, so admin CD keys can't leak through
// a shared module). Replaces the old hard-coded GetPCPublicCDKey() == "..." lists.
//
// Schema:  admins(cdkey PK, name, can_admin, can_homeless, can_chest, added_at)
//
// The whitelist is seeded/maintained OUT OF BAND with sqlite3 (see the gitignored
// bin/seed-admindb.sh). Module scripts only ever SELECT — no keys live in source.

const string ADMIN_DB = "admindb";

// ------------------------------------------------------------
// Schema

void Admin_InitDb()
{
    sqlquery q = SqlPrepareQueryCampaign(ADMIN_DB,
        "CREATE TABLE IF NOT EXISTS admins (" +
        "cdkey TEXT PRIMARY KEY," +
        "name TEXT," +
        "can_admin INTEGER DEFAULT 0," +
        "can_homeless INTEGER DEFAULT 0," +
        "can_chest INTEGER DEFAULT 0," +
        "added_at TEXT DEFAULT (datetime('now')))");
    SqlStep(q);
}

// ------------------------------------------------------------
// Authorization checks. Each returns TRUE/FALSE for the speaking/using PC.
// Column names can't be bound, so there is one literal query per tier.

int Admin_CanAdmin(object oPC)
{
    sqlquery q = SqlPrepareQueryCampaign(ADMIN_DB,
        "SELECT can_admin FROM admins WHERE cdkey=@k");
    SqlBindString(q, "@k", GetPCPublicCDKey(oPC));
    if (!SqlStep(q)) return FALSE;
    return SqlGetInt(q, 0);
}

int Admin_CanHomeless(object oPC)
{
    sqlquery q = SqlPrepareQueryCampaign(ADMIN_DB,
        "SELECT can_homeless FROM admins WHERE cdkey=@k");
    SqlBindString(q, "@k", GetPCPublicCDKey(oPC));
    if (!SqlStep(q)) return FALSE;
    return SqlGetInt(q, 0);
}

int Admin_CanChest(object oPC)
{
    sqlquery q = SqlPrepareQueryCampaign(ADMIN_DB,
        "SELECT can_chest FROM admins WHERE cdkey=@k");
    SqlBindString(q, "@k", GetPCPublicCDKey(oPC));
    if (!SqlStep(q)) return FALSE;
    return SqlGetInt(q, 0);
}
