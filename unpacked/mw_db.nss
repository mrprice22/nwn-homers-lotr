// mw_db.nss - persistence for Meaningwave guide progress (unlocks, journal
// stages, the finale grant, the mixtape consumption), keyed on
// GetObjectUUID() - one row per character per flag. Shaped like legfeat_db.nss.
//
// WHY THIS EXISTS. The old scheme used GetCampaignInt/SetCampaignInt("meaningwave",
// key, oPC), which lets the engine derive its own row key from
// GetPCPlayerName(oPC) (the account's chosen display name, NOT the CD key)
// + character first/last name, silently truncated to a short fixed length
// (observed max ~29-30 bytes). Most rows in that DB end up per-character by
// accident, but two characters on one account whose combined name strings
// share a long enough prefix collide onto the same row (roadmap:
// mw-mixtape-per-character, reported by -Methonash- 2026-09-09 - both of
// their characters truncate to the identical key). A UUID never collides
// and never truncates.
//
// MIGRATING OLD PROGRESS runs on two complementary tracks:
//
//   * LIVE, per character, in MW_MigrateLegacy() (mw_unlock_inc.nss, where
//     the 7-guide roster helpers it needs already live): it asks the engine
//     the exact same question it always could (GetCampaignInt(MW_LEGACY_DB,
//     key, oPC) for the PC that is actually logged in right now), which is
//     authoritative because it is the very same lookup that produced the bug.
//   * OFFLINE, in bin/audit-meaningwave-legacy.py, which reuses the identity
//     bridge GIT/nwn_manager's own wiki build already relies on
//     (nwn_wiki.players.identity/bicreader) to cross-reference
//     activity-sessions.json (account name <-> CD key) against the vault, so
//     it CAN resolve most old rows to a specific character without waiting
//     for a login - useful for reviewing mw_legacy_pending ahead of time,
//     or for an account that never logs back in. (An earlier version of
//     this comment claimed no offline resolution was possible at all; that
//     was wrong - it just needed the same bridge the wiki already built.)
//
// Neither track can tell "the same character, still around" apart from "a
// new character somebody gave the same name" when two characters on one
// account genuinely collide (that IS the root cause) - both report those
// as ambiguous rather than guessing. So only the LOW-STAKES flags
// (u_<guide>, jq_*: no permanent effect - guide buffs don't survive
// dismissal, and the XP is small and bounded) are ever carried forward
// automatically, and only on an unambiguous match. "finale" and
// "mixtape_consumed" gate a PERMANENT +1 to all six base ability scores;
// granting that twice for one playthrough, or reattaching it to a character
// that never earned it, is the exploit this must never cause. Those two are
// only ever logged to mw_legacy_pending for the admin to resolve by hand
// (bin/list-mw-legacy-pending.py to review/apply what the live path found,
// bin/audit-meaningwave-legacy.py for the richer offline cross-reference).
//
// THAT SPLIT WAS NOT SAFE ON ITS OWN, and the correction is the whole reason
// the two guards below exist (roadmap:
// can-complete-meaningwave-questline-for-free-on-characters, reported by
// Szescian82 2026-09-15). Carrying the u_* flags forward while refusing to
// carry "finale"/"mixtape_consumed" hands a new character the PREREQUISITE
// for the reward without the ALREADY-CLAIMED marker: mw_finale_chk.nss only
// asks for 7 unlocks and no "finale", so a freshly rolled character with the
// SAME NAME as a finished one read that finished character's legacy row,
// walked to Akira and took the permanent +1 to all six abilities for free -
// repeatable on every re-roll of the name. (Observed on the live realm:
// one account collected it seven times in four days.) Two guards, both in
// MW_MigrateLegacy():
//
//   1. A legacy row that carries "finale" or "mixtape_consumed" is a
//      playthrough that has already paid out. Migrate NOTHING from it - log
//      the sensitive flags to mw_legacy_pending and stop. The genuine owner
//      is restored by the admin, which is already the designed route.
//   2. mw_legacy_claim: each legacy row may be consumed by exactly ONE
//      character, ever. This covers the residual case guard 1 misses - a
//      first character that unlocked all 7 guides but never took the
//      Mixtape, so "finale" is unset and there is nothing for guard 1 to
//      see. The claim key is GetPCPublicCDKey() + "|" + GetName(), the same
//      account+character-name domain the engine's legacy key collides in,
//      but read from the live PC so it is never truncated.

const string MW_FLAG_DB   = "meaningwavedb";
const string MW_LEGACY_DB = "meaningwave";

void MW_InitDb();
int  MW_GetFlag(object oPC, string sFlag);
void MW_SetFlag(object oPC, string sFlag);
int  MW_ClaimLegacyRow(object oPC);

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

    // Guard 2 (see the header): one legacy row, one character, forever.
    q = SqlPrepareQueryCampaign(MW_FLAG_DB,
        "CREATE TABLE IF NOT EXISTS mw_legacy_claim (" +
        "claim_key TEXT NOT NULL PRIMARY KEY, pid TEXT NOT NULL," +
        "claimed_at TEXT DEFAULT CURRENT_TIMESTAMP)");
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

// Stake oPC's claim on the legacy row for its account+character-name identity.
// Returns TRUE only if oPC is the character that holds that claim - i.e. it
// just took it, or it took it on an earlier login. A second character sharing
// the name loses the race permanently and migrates nothing. INSERT OR IGNORE
// makes the first writer the winner; the SELECT is what decides, so a repeat
// call for the same character is still TRUE.
int MW_ClaimLegacyRow(object oPC)
{
    string sKey = GetPCPublicCDKey(oPC) + "|" + GetName(oPC);
    string sPid = GetObjectUUID(oPC);

    sqlquery q = SqlPrepareQueryCampaign(MW_FLAG_DB,
        "INSERT OR IGNORE INTO mw_legacy_claim(claim_key, pid) VALUES(@k, @p)");
    SqlBindString(q, "@k", sKey);
    SqlBindString(q, "@p", sPid);
    SqlStep(q);

    q = SqlPrepareQueryCampaign(MW_FLAG_DB,
        "SELECT pid FROM mw_legacy_claim WHERE claim_key=@k LIMIT 1");
    SqlBindString(q, "@k", sKey);
    if (!SqlStep(q)) return FALSE;
    return SqlGetString(q, 0) == sPid;
}
