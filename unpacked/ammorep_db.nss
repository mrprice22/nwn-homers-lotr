// ammorep_db.nss - persistence for the Quiver of Endless Flight (ammo replicator).
//
// The quiver is a boss drop (Legolas Greenleaf, Angmar) that can be used twice
// before it crumbles. The remaining uses are NOT normal item charges - they live
// in the campaign SQLite DB "ammorepdb", keyed on the ITEM's own UUID.
//
// Keying on the item (not the holder) is the point: a half-used quiver stays
// half-used when it is dropped, traded, pickpocketed or left in a chest. The new
// owner sees 1 use left, not a fresh 2. GetObjectUUID assigns on first read and
// is serialised with the item, so the key survives inventory transfer, logout and
// the character vault.
//
// Mirrors the style of dye_db.nss / brd_db.nss.

const string AMMOREP_DB   = "ammorepdb";
const int    AMMOREP_USES = 2;     // uses per quiver before it crumbles
const int    AMMOREP_GRANT = 500;  // units of the chosen ammo granted per use

// Idempotent - called from onmoduleload.nss.
void AmmoRep_InitDb()
{
    sqlquery q = SqlPrepareQueryCampaign(AMMOREP_DB,
        "CREATE TABLE IF NOT EXISTS replicators (" +
        "uuid TEXT PRIMARY KEY, uses_left INTEGER NOT NULL, first_used TEXT)");
    SqlStep(q);
}

// Uses left on this quiver. An unregistered quiver (never used) has no row and
// reports the full AMMOREP_USES.
int AmmoRep_UsesLeft(object oItem)
{
    if (!GetIsObjectValid(oItem)) return 0;

    sqlquery q = SqlPrepareQueryCampaign(AMMOREP_DB,
        "SELECT uses_left FROM replicators WHERE uuid=@u LIMIT 1");
    SqlBindString(q, "@u", GetObjectUUID(oItem));
    if (!SqlStep(q)) return AMMOREP_USES;
    return SqlGetInt(q, 0);
}

// Burn one use. Returns the number of uses REMAINING afterwards (0 = it crumbles).
int AmmoRep_Consume(object oItem)
{
    int nLeft = AmmoRep_UsesLeft(oItem) - 1;
    if (nLeft < 0) nLeft = 0;

    sqlquery q = SqlPrepareQueryCampaign(AMMOREP_DB,
        "INSERT INTO replicators(uuid, uses_left, first_used)" +
        " VALUES(@u, @n, datetime('now'))" +
        " ON CONFLICT(uuid) DO UPDATE SET uses_left=excluded.uses_left");
    SqlBindString(q, "@u", GetObjectUUID(oItem));
    SqlBindInt(q, "@n", nLeft);
    SqlStep(q);

    return nLeft;
}
