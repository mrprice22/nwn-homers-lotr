// mw_db.nss - persistence for Meaningwave guide progress (unlocks, journal
// stages, the finale grant, the mixtape consumption), keyed on
// GetObjectUUID() - one row per character per flag. Shaped like legfeat_db.nss.
//
// WHY THIS EXISTS. The old scheme used GetCampaignInt/SetCampaignInt("meaningwave",
// key, oPC), which lets the engine derive its own row key from CD key +
// character first/last name, silently truncated to a short fixed length.
// Most rows in that DB end up per-character by accident, but two characters
// on one account whose combined CD-key+name strings share a long enough
// prefix collide onto the same row (roadmap: mw-mixtape-per-character,
// reported by -Methonash- 2026-09-09 - both of their characters truncate to
// the identical key). A UUID never collides and never truncates.
//
// MIGRATING OLD PROGRESS. There is no reliable OFFLINE way to match an old
// row back to a specific character: the playerid the engine wrote embeds
// GetPCPublicCDKey(oPC) + GetName(oPC), but servervault's own folder names
// are a different, opaque engine hash of the CD key - the two don't decode
// into each other in a script outside the game. So migration runs LIVE, per
// character, in MW_MigrateLegacy() (mw_unlock_inc.nss, where the 7-guide
// roster helpers it needs already live): it asks the engine the exact same
// question it always could (GetCampaignInt(MW_LEGACY_DB, key, oPC) for the
// PC that is actually logged in right now), which is authoritative because
// it is the very same lookup that produced the bug - no guessing needed.
//
// That still cannot tell "the same character, still around" apart from "a
// new character somebody gave the same name" - the old system never could
// either, which is the root cause. So only the LOW-STAKES flags (u_<guide>,
// jq_*: no permanent effect - guide buffs don't survive dismissal, and the
// XP is small and bounded) are carried forward automatically. "finale" and
// "mixtape_consumed" gate a PERMANENT +1 to all six base ability scores;
// granting that twice for one playthrough, or reattaching it to a character
// that never earned it, is the exploit this script must never cause. Those
// two are only ever logged to mw_legacy_pending for the admin to resolve by
// hand (query the table directly, or see bin/list-mw-legacy-pending.py).

const string MW_FLAG_DB   = "meaningwavedb";
const string MW_LEGACY_DB = "meaningwave";

void MW_InitDb();
int  MW_GetFlag(object oPC, string sFlag);
void MW_SetFlag(object oPC, string sFlag);

// Idempotent - safe to call on every module load.
void MW_InitDb()
{
    sqlquery q = SqlPrepareQueryCampaign(MW_FLAG_DB,
        "CREATE TABLE IF NOT EXISTS mw_flag (" +
        "pid TEXT NOT NULL, flag TEXT NOT NULL, cdkey TEXT," +
        "set_at TEXT DEFAULT CURRENT_TIMESTAMP," +
        "PRIMARY KEY(pid, flag))");
    SqlStep(q);

    // Sensitive legacy flags (finale/mixtape_consumed) found on a character
    // that has no new-system row for them yet - never auto-applied, just
    // recorded for the admin. See MW_MigrateLegacy() below.
    q = SqlPrepareQueryCampaign(MW_FLAG_DB,
        "CREATE TABLE IF NOT EXISTS mw_legacy_pending (" +
        "pid TEXT NOT NULL, flag TEXT NOT NULL, cdkey TEXT, name TEXT," +
        "found_at TEXT DEFAULT CURRENT_TIMESTAMP," +
        "PRIMARY KEY(pid, flag))");
    SqlStep(q);
}

int MW_GetFlag(object oPC, string sFlag)
{
    sqlquery q = SqlPrepareQueryCampaign(MW_FLAG_DB,
        "SELECT 1 FROM mw_flag WHERE pid=@p AND flag=@f LIMIT 1");
    SqlBindString(q, "@p", GetObjectUUID(oPC));
    SqlBindString(q, "@f", sFlag);
    return SqlStep(q);
}

// INSERT OR IGNORE: setting the same flag twice is a no-op rather than an
// error, so a double-fired trigger can't clobber the original set_at.
void MW_SetFlag(object oPC, string sFlag)
{
    sqlquery q = SqlPrepareQueryCampaign(MW_FLAG_DB,
        "INSERT OR IGNORE INTO mw_flag(pid, flag, cdkey) VALUES(@p, @f, @k)");
    SqlBindString(q, "@p", GetObjectUUID(oPC));
    SqlBindString(q, "@f", sFlag);
    SqlBindString(q, "@k", GetPCPublicCDKey(oPC));
    SqlStep(q);
}
