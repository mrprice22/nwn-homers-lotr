// ptm_db.nss - per-character play time.
//
// Campaign DB "playtimedb" (file database/playtimedb.sqlite3):
//
//   sessions(id, uuid, char_name, cdkey, player_name, entered_at, left_at,
//            minutes)
//   meta(key, value)                          -- "tracking_started" timestamp
//
// WHY THIS EXISTS. The server log names only the ACCOUNT on login
// ("Playername (CDKEY) Joined as Player 1"), never the character, so the wiki
// could report hours per account but never per character - every character an
// account owned showed that account's total. Nothing else on the server
// recorded it either. This table is the missing fact.
//
// Identity is split as in bst_db.nss and cbd_db.nss: `uuid` (GetObjectUUID) is
// the CHARACTER, `cdkey` (GetPCPublicCDKey) is the ACCOUNT.
//
// THE TRAP: a crash, a kill -9 or the nightly reboot never fires
// Mod_OnClientLeav, so those rows would stay open forever and, once closed by
// a later login, count every hour the server was down as play time. Ptm_Open()
// therefore closes any row this character left open BEFORE inserting a new one,
// and Ptm_CloseStale() runs on module load to sweep rows left open by the
// previous run. Both mark the row abandoned (left_at NULL, minutes NULL) rather
// than guessing a duration -- an unknown session length is recorded as unknown,
// not as zero and not as "until now". This mirrors how the wiki's log parser
// discards sessions that were open across a restart marker.

const string PTM_DB = "playtimedb";

void Ptm_InitDb()
{
    sqlquery q = SqlPrepareQueryCampaign(PTM_DB,
        "CREATE TABLE IF NOT EXISTS sessions (" +
        "id INTEGER PRIMARY KEY AUTOINCREMENT," +
        "uuid TEXT NOT NULL," +
        "char_name TEXT," +
        "cdkey TEXT," +
        "player_name TEXT," +
        "entered_at TEXT NOT NULL DEFAULT (datetime('now'))," +
        "left_at TEXT," +
        "minutes REAL)");
    SqlStep(q);

    q = SqlPrepareQueryCampaign(PTM_DB,
        "CREATE INDEX IF NOT EXISTS idx_ptm_uuid ON sessions(uuid)");
    SqlStep(q);

    q = SqlPrepareQueryCampaign(PTM_DB,
        "CREATE TABLE IF NOT EXISTS meta (key TEXT PRIMARY KEY, value TEXT)");
    SqlStep(q);

    // Stamped once, on the very first module load after this ships. The wiki
    // prints it so nobody reads a character's 3 hours as its whole history:
    // season 2 was months old when counting started, and a figure without that
    // date is quietly wrong.
    q = SqlPrepareQueryCampaign(PTM_DB,
        "INSERT OR IGNORE INTO meta (key, value) " +
        "VALUES ('tracking_started', datetime('now'))");
    SqlStep(q);
}

// Close rows the previous server run left open. Called from module load, before
// any player can connect.
void Ptm_CloseStale()
{
    sqlquery q = SqlPrepareQueryCampaign(PTM_DB,
        "UPDATE sessions SET left_at = NULL, minutes = NULL " +
        "WHERE left_at IS NULL AND minutes IS NULL");
    SqlStep(q);
}

void Ptm_Open(object oPC)
{
    if (!GetIsPC(oPC) || GetIsDM(oPC)) return;
    string sUuid = GetObjectUUID(oPC);
    if (sUuid == "") return;

    // Belt and braces: this character may hold an open row from a run that
    // ended without a clean logout. Leave it abandoned rather than crediting it.
    sqlquery q = SqlPrepareQueryCampaign(PTM_DB,
        "UPDATE sessions SET minutes = NULL WHERE uuid = @u AND left_at IS NULL");
    SqlBindString(q, "@u", sUuid);
    SqlStep(q);

    q = SqlPrepareQueryCampaign(PTM_DB,
        "INSERT INTO sessions (uuid, char_name, cdkey, player_name) " +
        "VALUES (@u, @c, @k, @p)");
    SqlBindString(q, "@u", sUuid);
    SqlBindString(q, "@c", GetName(oPC));
    SqlBindString(q, "@k", GetPCPublicCDKey(oPC));
    SqlBindString(q, "@p", GetPCPlayerName(oPC));
    SqlStep(q);
}

void Ptm_Close(object oPC)
{
    if (!GetIsPC(oPC) || GetIsDM(oPC)) return;
    string sUuid = GetObjectUUID(oPC);
    if (sUuid == "") return;

    // Close only the newest open row for this character, and let SQLite compute
    // the duration from the two timestamps -- the module has no wall clock it
    // can trust across a reboot.
    sqlquery q = SqlPrepareQueryCampaign(PTM_DB,
        "UPDATE sessions SET left_at = datetime('now'), " +
        "minutes = (julianday('now') - julianday(entered_at)) * 1440.0 " +
        "WHERE id = (SELECT id FROM sessions WHERE uuid = @u " +
        "AND left_at IS NULL ORDER BY id DESC LIMIT 1)");
    SqlBindString(q, "@u", sUuid);
    SqlStep(q);
}
