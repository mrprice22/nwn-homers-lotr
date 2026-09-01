// ptm_db.nss - per-character play time.
//
// Campaign DB "playtimedb" (file database/playtimedb.sqlite3):
//
//   sessions(id, uuid, char_name, cdkey, player_name, entered_at, left_at,
//            minutes)
//   ptm_meta(key, value)                      -- "tracking_started" timestamp
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
// WHY "ptm_meta" AND NOT "meta". `meta` is RESERVED BY THE ENGINE. NWN:EE
// pre-seeds every campaign DB with three internal tables - `migrations`, `db`
// and `meta` - and its SQL authorizer DENIES any script statement naming one of
// them, with "sqlite error: not authorized (code=23)". This shipped as `meta`
// and so failed on every single login, permanently and silently apart from the
// error in the player's log; tracking_started was never stamped. Never name a
// campaign-DB table `meta`, `db` or `migrations`.
//
// THE TRAP: a crash, a kill -9 or the nightly reboot never fires
// Mod_OnClientLeav, so those rows stay open forever. They must never be closed
// retroactively, or a later read would count every hour the server was down as
// play time. The rule is enforced BY THE READER, not by a sweep: an open row is
// exactly one whose `minutes` is NULL (INSERT never sets it), and the wiki sums
// only `WHERE minutes IS NOT NULL`. Ptm_Close() closes only the newest open row
// for the character (ORDER BY id DESC LIMIT 1), so an abandoned row is never
// mistakenly credited to a later session. An unknown session length stays
// unknown - not zero, not "until now". This mirrors how the wiki's log parser
// discards sessions left open across a restart marker.

const string PTM_DB = "playtimedb";

// Schema setup. Called from onmoduleload ONLY - never from the client-enter
// hook. DDL is a synchronous commit against a campaign DB file, and on this box
// (one spinning disk, single-threaded server main loop) doing that on the login
// frame is a stall players feel as lag.
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
        "CREATE TABLE IF NOT EXISTS ptm_meta (key TEXT PRIMARY KEY, value TEXT)");
    SqlStep(q);

    // Stamped once. The wiki prints it so nobody reads a character's 3 hours as
    // its whole history: the season long predates counting, and a figure without
    // that date is quietly wrong. Seeded from the EARLIEST session rather than
    // from now, because sessions have been recording since 2026-08-29 while this
    // stamp could not be written at all - stamping "now" would understate the
    // window we actually have data for. COALESCE covers a fresh, empty DB.
    q = SqlPrepareQueryCampaign(PTM_DB,
        "INSERT OR IGNORE INTO ptm_meta (key, value) " +
        "SELECT 'tracking_started', COALESCE(MIN(entered_at), datetime('now')) " +
        "FROM sessions");
    SqlStep(q);
}

void Ptm_Open(object oPC)
{
    if (!GetIsPC(oPC) || GetIsDM(oPC)) return;
    string sUuid = GetObjectUUID(oPC);
    if (sUuid == "") return;

    // One statement, and the only DB work on the login frame. Any row this
    // character left open by a crash or reboot simply stays open with a NULL
    // `minutes` and is skipped by every reader - see THE TRAP above.
    sqlquery q = SqlPrepareQueryCampaign(PTM_DB,
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
