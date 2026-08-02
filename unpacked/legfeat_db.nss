// legfeat_db.nss — persistence for Legendary Feats (level-60 feat picks).
//
// Campaign SQLite DB "legfeatdb", keyed on GetObjectUUID() — one row per
// character per feat taken, plus a per-character row recording how many picks
// that character was granted. Shaped like bestiarydb / meritdb / dyedb.
//
// WHY THE DB EXISTS AT ALL. The feat itself persists in the .bic, so the
// character sheet remembers it without our help. What does NOT persist is:
//
//   * how many picks the character is still owed (a dismissed or half-finished
//     picker has to be recoverable — that is the rest-menu re-entry), and
//   * the fact that we already granted this character its allotment, so a relog
//     at level 60 must not hand out a second set.
//
// The feat rows are also kept, rather than read back off the character, because
// they are what a revoke undoes. Reading GetHasFeat() cannot tell a picked feat
// from one a DM added by hand, and after a revoke has to know exactly what was
// granted in order to take the base-score points back.
//
// legfeat_alloc also stores the CLASS SIGNATURE the allotment was computed from
// (sorted class ids, no levels). Comparing it is how a relevel is detected: the
// signature fully determines the allotment, and excludes levels so 59 -> 60 does
// not look like a change.
//
// See CLAUDE-legendary-feats.md ("Phase 3 — the picker NUI").

const string LEGFEAT_DB = "legfeatdb";

void   LegFeat_InitDb();
int    LegFeat_GetGranted(object oPC);
string LegFeat_GetClassSig(object oPC);
void   LegFeat_SetAlloc(object oPC, int nPicks, string sClassSig);
void   LegFeat_ClearAlloc(object oPC);
int    LegFeat_GetSpent(object oPC);
void   LegFeat_RecordPick(object oPC, int nFeatId);
int    LegFeat_HasPick(object oPC, int nFeatId);
void   LegFeat_ClearPicks(object oPC);

// Idempotent — safe to call on every login and every window open.
void LegFeat_InitDb()
{
    sqlquery q = SqlPrepareQueryCampaign(LEGFEAT_DB,
        "CREATE TABLE IF NOT EXISTS legfeat_alloc (" +
        "pid TEXT PRIMARY KEY, cdkey TEXT, picks INTEGER NOT NULL," +
        "class_sig TEXT NOT NULL DEFAULT ''," +
        "granted_at TEXT DEFAULT CURRENT_TIMESTAMP)");
    SqlStep(q);

    q = SqlPrepareQueryCampaign(LEGFEAT_DB,
        "CREATE TABLE IF NOT EXISTS legfeat_pick (" +
        "pid TEXT NOT NULL, feat INTEGER NOT NULL, cdkey TEXT," +
        "taken_at TEXT DEFAULT CURRENT_TIMESTAMP," +
        "PRIMARY KEY(pid, feat))");
    SqlStep(q);
}

// How many picks this character has been granted in total. 0 = never reached
// the allotment step, which is NOT the same as "has spent them all".
int LegFeat_GetGranted(object oPC)
{
    sqlquery q = SqlPrepareQueryCampaign(LEGFEAT_DB,
        "SELECT picks FROM legfeat_alloc WHERE pid=@p LIMIT 1");
    SqlBindString(q, "@p", GetObjectUUID(oPC));
    if (!SqlStep(q)) return 0;
    return SqlGetInt(q, 0);
}

// The class signature the stored allotment was computed from. "" = no row.
string LegFeat_GetClassSig(object oPC)
{
    sqlquery q = SqlPrepareQueryCampaign(LEGFEAT_DB,
        "SELECT class_sig FROM legfeat_alloc WHERE pid=@p LIMIT 1");
    SqlBindString(q, "@p", GetObjectUUID(oPC));
    if (!SqlStep(q)) return "";
    return SqlGetString(q, 0);
}

// Record the allotment and the class signature it was derived from. Written with
// a fixed value rather than incremented, which is what makes every caller of
// LegFeat_EnsureAllotment safe to re-fire.
void LegFeat_SetAlloc(object oPC, int nPicks, string sClassSig)
{
    sqlquery q = SqlPrepareQueryCampaign(LEGFEAT_DB,
        "INSERT INTO legfeat_alloc(pid, cdkey, picks, class_sig)" +
        " VALUES(@p, @k, @n, @s)" +
        " ON CONFLICT(pid) DO UPDATE SET picks=excluded.picks," +
        " class_sig=excluded.class_sig");
    SqlBindString(q, "@p", GetObjectUUID(oPC));
    SqlBindString(q, "@k", GetPCPublicCDKey(oPC));
    SqlBindInt(q, "@n", nPicks);
    SqlBindString(q, "@s", sClassSig);
    SqlStep(q);
}

// Drop the allotment entirely — used when a character falls below level 60, so
// the picks are re-earned rather than banked on the way back up.
void LegFeat_ClearAlloc(object oPC)
{
    sqlquery q = SqlPrepareQueryCampaign(LEGFEAT_DB,
        "DELETE FROM legfeat_alloc WHERE pid=@p");
    SqlBindString(q, "@p", GetObjectUUID(oPC));
    SqlStep(q);
}

int LegFeat_GetSpent(object oPC)
{
    sqlquery q = SqlPrepareQueryCampaign(LEGFEAT_DB,
        "SELECT COUNT(*) FROM legfeat_pick WHERE pid=@p");
    SqlBindString(q, "@p", GetObjectUUID(oPC));
    if (!SqlStep(q)) return 0;
    return SqlGetInt(q, 0);
}

// INSERT OR IGNORE: taking the same feat twice is a no-op rather than a second
// row, so a double-clicked button cannot burn two picks on one feat.
void LegFeat_RecordPick(object oPC, int nFeatId)
{
    sqlquery q = SqlPrepareQueryCampaign(LEGFEAT_DB,
        "INSERT OR IGNORE INTO legfeat_pick(pid, feat, cdkey)" +
        " VALUES(@p, @f, @k)");
    SqlBindString(q, "@p", GetObjectUUID(oPC));
    SqlBindInt(q, "@f", nFeatId);
    SqlBindString(q, "@k", GetPCPublicCDKey(oPC));
    SqlStep(q);
}

int LegFeat_HasPick(object oPC, int nFeatId)
{
    sqlquery q = SqlPrepareQueryCampaign(LEGFEAT_DB,
        "SELECT 1 FROM legfeat_pick WHERE pid=@p AND feat=@f LIMIT 1");
    SqlBindString(q, "@p", GetObjectUUID(oPC));
    SqlBindInt(q, "@f", nFeatId);
    return SqlStep(q);
}

// Forget every pick this character has taken. The caller is responsible for
// having already taken the feats and their benefits back off the character —
// this only clears the record.
void LegFeat_ClearPicks(object oPC)
{
    sqlquery q = SqlPrepareQueryCampaign(LEGFEAT_DB,
        "DELETE FROM legfeat_pick WHERE pid=@p");
    SqlBindString(q, "@p", GetObjectUUID(oPC));
    SqlStep(q);
}
