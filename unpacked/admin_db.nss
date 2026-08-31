// admin_db.nss - Admin whitelist database helpers
//
// Campaign DB: "admindb" (SQLite, lives in the server's database/ folder on the
// physical machine - never part of the .mod, so admin CD keys can't leak through
// a shared module). Replaces the old hard-coded GetPCPublicCDKey() == "..." lists.
//
// Schema:  admins(cdkey PK, name, can_admin, can_homeless, can_chest, can_merit,
//                 added_at)
//          houses(cdkey PK, player_name, area_tag UNIQUE, home_wp_tag,
//                 key_resref, added_at)
//
// The whitelist (and the per-CD-key player-house rows) are seeded/maintained OUT
// OF BAND with sqlite3 (see the gitignored bin/seed-admindb.sh). Module scripts
// only ever SELECT - no CD keys live in source.

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
        "can_merit INTEGER DEFAULT 0," +
        "added_at TEXT DEFAULT (datetime('now')))");
    SqlStep(q);

    // Migration: the admins table predates can_merit, and CREATE TABLE IF NOT
    // EXISTS will not add a column to a table that already exists - so on every
    // server that already has an admindb this is the only thing that backfills
    // it. Same shape as the uat migration in merit_db.nss; PRAGMA table_info is
    // checked first so a boot with the column present does not log a SQL error.
    // DEFAULT 0 is the safety property: an existing admin gets no merit powers
    // until bin/seed-admindb.sh grants them explicitly.
    int bHasMerit = FALSE;
    sqlquery qp = SqlPrepareQueryCampaign(ADMIN_DB, "PRAGMA table_info(admins)");
    while (SqlStep(qp))
        if (SqlGetString(qp, 1) == "can_merit") { bHasMerit = TRUE; break; }
    if (!bHasMerit)
    {
        sqlquery qa = SqlPrepareQueryCampaign(ADMIN_DB,
            "ALTER TABLE admins ADD COLUMN can_merit INTEGER DEFAULT 0");
        SqlStep(qa);
    }

    // Player-house ownership: one home per CD key. Maps a CD key to its home
    // teleport waypoint, the area it owns (ownership anchor for the in-house
    // chest + key-ring), and the door-key resref the key-ring dispenses.
    sqlquery h = SqlPrepareQueryCampaign(ADMIN_DB,
        "CREATE TABLE IF NOT EXISTS houses (" +
        "cdkey TEXT PRIMARY KEY," +
        "player_name TEXT," +
        "area_tag TEXT UNIQUE," +
        "home_wp_tag TEXT," +
        "key_resref TEXT," +
        "added_at TEXT DEFAULT (datetime('now')))");
    SqlStep(h);
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

// The merit tier: awarding merit and fulfilling/cancelling redemption requests
// on the EmoteWand admin menu, and the redemption shop on a non-live realm.
// Deliberately narrower than can_admin - a DM can hold every other admin power
// without being able to move the merit economy, which is account-wide and
// shared across seasons.
int Admin_CanMerit(object oPC)
{
    sqlquery q = SqlPrepareQueryCampaign(ADMIN_DB,
        "SELECT can_merit FROM admins WHERE cdkey=@k");
    SqlBindString(q, "@k", GetPCPublicCDKey(oPC));
    if (!SqlStep(q)) return FALSE;
    return SqlGetInt(q, 0);
}

// ------------------------------------------------------------
// Player-house ownership (houses table). All SELECT-only, keyed by CD key /
// area tag. Used by the "Home" rest-menu teleport, the in-house persistent
// chest, and the key-ring. Adding a new player house is a data-entry job in
// bin/seed-admindb.sh - no script change needed.

// TRUE if this PC's CD key owns a home (any houses row).
int Admin_HasHome(object oPC)
{
    sqlquery q = SqlPrepareQueryCampaign(ADMIN_DB,
        "SELECT 1 FROM houses WHERE cdkey=@k");
    SqlBindString(q, "@k", GetPCPublicCDKey(oPC));
    return SqlStep(q);
}

// The "Home" teleport destination waypoint tag for this PC's CD key (or "").
string Admin_GetHomeWP(object oPC)
{
    sqlquery q = SqlPrepareQueryCampaign(ADMIN_DB,
        "SELECT home_wp_tag FROM houses WHERE cdkey=@k");
    SqlBindString(q, "@k", GetPCPublicCDKey(oPC));
    if (!SqlStep(q)) return "";
    return SqlGetString(q, 0);
}

// TRUE if this PC's CD key owns the house whose area tag is sAreaTag.
// Gate for the in-house persistent chest and key-ring.
int Admin_OwnsAreaHouse(object oPC, string sAreaTag)
{
    sqlquery q = SqlPrepareQueryCampaign(ADMIN_DB,
        "SELECT 1 FROM houses WHERE area_tag=@a AND cdkey=@k");
    SqlBindString(q, "@a", sAreaTag);
    SqlBindString(q, "@k", GetPCPublicCDKey(oPC));
    return SqlStep(q);
}

// The door-key item resref the key-ring of house sAreaTag dispenses (or "").
string Admin_GetHouseKeyResref(string sAreaTag)
{
    sqlquery q = SqlPrepareQueryCampaign(ADMIN_DB,
        "SELECT key_resref FROM houses WHERE area_tag=@a");
    SqlBindString(q, "@a", sAreaTag);
    if (!SqlStep(q)) return "";
    return SqlGetString(q, 0);
}
