// bst_db.nss — Bestiary / creature-kill-tracking database helpers
//
// Campaign DB: "bestiarydb" (SQLite, file database/bestiary.sqlite3)
//
// Tables:
//   kills        (uuid, cdkey, char_name, resref, solo_kills, party_kills, last_kill)
//                  PRIMARY KEY (uuid, resref) — per-character per-creature totals.
//                  Character identity is GetObjectUUID (persists in the .bic);
//                  cdkey kept so per-(character,cdkey) aggregation is possible.
//   server_first (resref PK, cr, first_uuid, first_name, first_cdkey, first_player_name, first_at)
//                  one row per hard creature (CR >= BST_SF_CR) first slain server-wide.
//   catalogue    (resref PK, name, cr) — every creature type, seeded by nwn-wiki.
//   resref_alias (resref PK, canonical) — maps blueprint/variant resrefs to the
//                  canonical resref used everywhere else, also seeded by nwn-wiki.
//
// Kills are recorded by CANONICAL resref (see Bst_Canonical) so the in-game
// bestiary, the per-creature confirmation, and the wiki stats all agree.

const string BST_DB    = "bestiarydb";
const float  BST_SF_CR = 60.0;   // "Server First" threshold (Challenge Rating)

// ------------------------------------------------------------
// Schema

void Bst_InitDb()
{
    sqlquery q;

    q = SqlPrepareQueryCampaign(BST_DB,
        "CREATE TABLE IF NOT EXISTS kills (" +
        "uuid TEXT NOT NULL," +
        "cdkey TEXT NOT NULL," +
        "char_name TEXT," +
        "resref TEXT NOT NULL," +
        "solo_kills INTEGER NOT NULL DEFAULT 0," +
        "party_kills INTEGER NOT NULL DEFAULT 0," +
        "last_kill TEXT," +
        "PRIMARY KEY (uuid, resref))");
    SqlStep(q);

    q = SqlPrepareQueryCampaign(BST_DB,
        "CREATE INDEX IF NOT EXISTS idx_kills_resref ON kills(resref)");
    SqlStep(q);

    q = SqlPrepareQueryCampaign(BST_DB,
        "CREATE TABLE IF NOT EXISTS server_first (" +
        "resref TEXT PRIMARY KEY," +
        "cr REAL," +
        "first_uuid TEXT," +
        "first_name TEXT," +
        "first_cdkey TEXT," +
        "first_player_name TEXT," +
        "first_at TEXT NOT NULL DEFAULT (datetime('now')))");
    SqlStep(q);
    // Migration: add first_player_name to pre-existing DBs. Guard with PRAGMA so the
    // ALTER is skipped on logins after the column already exists.
    q = SqlPrepareQueryCampaign(BST_DB,
        "SELECT 1 FROM pragma_table_info('server_first') WHERE name='first_player_name'");
    if (!SqlStep(q))
    {
        q = SqlPrepareQueryCampaign(BST_DB,
            "ALTER TABLE server_first ADD COLUMN first_player_name TEXT");
        SqlStep(q);
    }

    q = SqlPrepareQueryCampaign(BST_DB,
        "CREATE TABLE IF NOT EXISTS catalogue (" +
        "resref TEXT PRIMARY KEY, name TEXT, cr REAL)");
    SqlStep(q);

    q = SqlPrepareQueryCampaign(BST_DB,
        "CREATE TABLE IF NOT EXISTS resref_alias (" +
        "resref TEXT PRIMARY KEY, canonical TEXT NOT NULL)");
    SqlStep(q);
}

// ------------------------------------------------------------
// Recording

// Resolve an instance/blueprint resref to its canonical resref. Falls back to
// the input when no alias row exists (e.g. catalogue not yet seeded).
string Bst_Canonical(string sResref)
{
    sqlquery q = SqlPrepareQueryCampaign(BST_DB,
        "SELECT canonical FROM resref_alias WHERE resref=@r");
    SqlBindString(q, "@r", sResref);
    if (SqlStep(q)) return SqlGetString(q, 0);
    return sResref;
}

// Add one kill of sResref (already canonical) to a character's record.
// bParty TRUE -> party kill, FALSE -> solo kill.
void Bst_RecordKill(string sUuid, string sCdkey, string sName, string sResref, int bParty)
{
    sqlquery q = SqlPrepareQueryCampaign(BST_DB,
        "INSERT INTO kills(uuid,cdkey,char_name,resref,solo_kills,party_kills,last_kill)" +
        " VALUES(@u,@k,@n,@r,@s,@p,datetime('now'))" +
        " ON CONFLICT(uuid,resref) DO UPDATE SET" +
        " solo_kills=solo_kills+@s," +
        " party_kills=party_kills+@p," +
        " cdkey=excluded.cdkey," +
        " char_name=excluded.char_name," +
        " last_kill=excluded.last_kill");
    SqlBindString(q, "@u", sUuid);
    SqlBindString(q, "@k", sCdkey);
    SqlBindString(q, "@n", sName);
    SqlBindString(q, "@r", sResref);
    SqlBindInt(q, "@s", bParty ? 0 : 1);
    SqlBindInt(q, "@p", bParty ? 1 : 0);
    SqlStep(q);
}

// TRUE when sResref exists in the seeded creature catalogue. A kill of a
// creature NOT in the catalogue (script-spawned, or added since the last wiki
// refresh) is still recorded, but bst_ondeath logs it for DM review.
int Bst_InCatalogue(string sResref)
{
    sqlquery q = SqlPrepareQueryCampaign(BST_DB,
        "SELECT 1 FROM catalogue WHERE resref=@r");
    SqlBindString(q, "@r", sResref);
    return SqlStep(q);
}

// Total kills (solo+party) of sResref by a character — for the combat-log line.
int Bst_GetTotal(string sUuid, string sResref)
{
    sqlquery q = SqlPrepareQueryCampaign(BST_DB,
        "SELECT solo_kills + party_kills FROM kills WHERE uuid=@u AND resref=@r");
    SqlBindString(q, "@u", sUuid);
    SqlBindString(q, "@r", sResref);
    if (SqlStep(q)) return SqlGetInt(q, 0);
    return 0;
}

// Register the first server-wide kill of a hard creature. Returns TRUE only when
// this call created the row (i.e. it really was the server first).
int Bst_RegisterServerFirst(string sResref, float fCR, string sUuid, string sName, string sCdkey, string sPlayerName)
{
    sqlquery qc = SqlPrepareQueryCampaign(BST_DB,
        "SELECT 1 FROM server_first WHERE resref=@r");
    SqlBindString(qc, "@r", sResref);
    if (SqlStep(qc)) return FALSE;       // already recorded

    sqlquery q = SqlPrepareQueryCampaign(BST_DB,
        "INSERT INTO server_first(resref,cr,first_uuid,first_name,first_cdkey,first_player_name)" +
        " VALUES(@r,@c,@u,@n,@k,@pn) ON CONFLICT(resref) DO NOTHING");
    SqlBindString(q, "@r", sResref);
    SqlBindFloat (q, "@c", fCR);
    SqlBindString(q, "@u", sUuid);
    SqlBindString(q, "@n", sName);
    SqlBindString(q, "@k", sCdkey);
    SqlBindString(q, "@pn", sPlayerName);
    SqlStep(q);
    return TRUE;
}

// ------------------------------------------------------------
// Tracked bosses (browse mode 2 + the intro progress line)
//
// The boss set is the "Roll of the Fallen" registry in respawndb (the CR>60
// single-instance bosses — see CLAUDE-boss-tracker.md), i.e. exactly the set
// the forge's progressive bonus keys off: slay every one of them and the top
// forges grant +20% value cap and one extra property slot (forge_inc.nss,
// ForgeBossDistinctKills / ForgeBossBonusPct). Kept in this file rather than
// #include "forge_inc" — that include drags in the whole forge/appraise/colour
// stack, and bst_db is on the OnDeath hot path.

// Quoted, comma-separated list of every tracked boss resref (registry +
// aliases) for SQL IN(...). Resrefs are filenames (alphanumeric), so inlining
// them into SQL text is safe. Returns "''" (an IN-list that matches nothing)
// when respawndb is unavailable, so callers can splice it in unconditionally.
// Cached on the module: brd_db reseeds the registry only on module load.
string Bst_BossListSql()
{
    object oMod  = GetModule();
    string sList = GetLocalString(oMod, "BST_BOSS_LIST");
    if (sList != "") return sList;

    sqlquery q = SqlPrepareQueryCampaign("respawndb",
        "SELECT group_concat('''' || resref || '''') FROM" +
        " (SELECT resref FROM boss_registry UNION SELECT resref FROM boss_alias)");
    if (SqlStep(q)) sList = SqlGetString(q, 0);
    if (sList == "") sList = "''";
    SetLocalString(oMod, "BST_BOSS_LIST", sList);
    return sList;
}

// Number of bosses the registry tracks. 0 when unavailable.
int Bst_BossTotal()
{
    object oMod = GetModule();
    int nTotal  = GetLocalInt(oMod, "BST_BOSS_TOTAL");
    if (nTotal > 0) return nTotal;

    sqlquery q = SqlPrepareQueryCampaign("respawndb", "SELECT COUNT(*) FROM boss_registry");
    if (SqlStep(q))
    {
        nTotal = SqlGetInt(q, 0);
        SetLocalInt(oMod, "BST_BOSS_TOTAL", nTotal);
    }
    return nTotal;
}

// Quoted list of the REGISTRY-side resrefs this character has already slain.
// Bestiary kills are stored by canonical resref, so a registry resref counts as
// slain when the kill row matches it directly or matches its bestiary canonical.
// "''" when nothing has been slain.
string Bst_BossSlainSql(object oPC)
{
    string sAll = Bst_BossListSql();

    sqlquery q = SqlPrepareQueryCampaign(BST_DB,
        "SELECT group_concat('''' || r || '''') FROM (" +
        " SELECT resref AS r FROM kills WHERE uuid=@u AND resref IN (" + sAll + ")" +
        " UNION" +
        " SELECT a.resref AS r FROM resref_alias a JOIN kills k ON k.resref=a.canonical" +
        "  WHERE k.uuid=@u AND a.resref IN (" + sAll + "))");
    SqlBindString(q, "@u", GetObjectUUID(oPC));

    string sSlain;
    if (SqlStep(q)) sSlain = SqlGetString(q, 0);
    if (sSlain == "") sSlain = "''";
    return sSlain;
}

// Distinct tracked bosses this character has slain. Deliberately the same
// COUNT(DISTINCT) the forge uses, so the book's "x of y" and the forge's tier
// message can never disagree; clamped to the registry total.
int Bst_BossSlainCount(object oPC)
{
    string sAll = Bst_BossListSql();

    sqlquery q = SqlPrepareQueryCampaign(BST_DB,
        "SELECT COUNT(DISTINCT resref) FROM kills WHERE uuid=@u" +
        " AND (resref IN (" + sAll + ")" +
        " OR resref IN (SELECT canonical FROM resref_alias WHERE resref IN (" + sAll + ")))");
    SqlBindString(q, "@u", GetObjectUUID(oPC));

    int nKills = 0;
    if (SqlStep(q)) nKills = SqlGetInt(q, 0);

    int nTotal = Bst_BossTotal();
    if (nTotal > 0 && nKills > nTotal) nKills = nTotal;
    return nKills;
}

// Token 5029 — the boss-progress line on the book's index page. Must be set
// BEFORE the index entry is spoken (token substitution happens at display), so
// it is driven from the item-activation script and the [Back to the index]
// reply, not from the entry node's own action script.
void Bst_BuildIntro(object oPC)
{
    int nTotal = Bst_BossTotal();
    if (nTotal <= 0)
    {
        SetCustomToken(5029, "");
        return;
    }

    int nSlain = Bst_BossSlainCount(oPC);
    string sLine = "Great foes felled: " + IntToString(nSlain) + " of " + IntToString(nTotal) + ".";

    if (nSlain >= nTotal)
        sLine += " Not one remains — the great forges yield their final property slot to you.";
    else
        sLine += " Fell them all and the great forges will yield one more property slot.";

    SetCustomToken(5029, sLine);
}

// ------------------------------------------------------------
// In-game bestiary menu (book conversation). Tokens 5029-5041.
//   local int    "bst_mode"       0 = Creatures Slain, 1 = Not Yet Slain,
//                                 2 = Bosses Not Yet Slain
//   local int    "bst_page_off"   row offset (multiples of 9)
//   local int    "bst_page_total" total rows in the section (set here)
//   local string "bst_slot_N_resref" canonical resref shown in slot N
// Mirrors Merit_BuildPage in merit_db.nss.

void Bst_BuildPage(object oPC)
{
    int    nMode = GetLocalInt(oPC, "bst_mode");
    int    nOff  = GetLocalInt(oPC, "bst_page_off");
    string sUuid = GetObjectUUID(oPC);

    // Mode 2 reads the boss registry out of respawndb instead of the bestiary
    // catalogue; the "already slain" set is spliced in as a literal IN-list
    // because the two campaign DBs cannot be joined in one query.
    string sSlain, sBossWhere;
    if (nMode == 2)
    {
        sSlain     = Bst_BossSlainSql(oPC);
        sBossWhere = " WHERE resref NOT IN (" + sSlain + ")" +
                     " AND resref NOT IN (SELECT canonical FROM boss_alias" +
                     "                    WHERE resref IN (" + sSlain + "))";
    }

    // Section row count (for pagination + [Next >>] visibility).
    sqlquery qc;
    if (nMode == 2)
        qc = SqlPrepareQueryCampaign("respawndb",
            "SELECT COUNT(*) FROM boss_registry" + sBossWhere);
    else if (nMode == 0)
        qc = SqlPrepareQueryCampaign(BST_DB,
            "SELECT COUNT(*) FROM catalogue c" +
            " JOIN kills k ON k.resref=c.resref WHERE k.uuid=@u");
    else
        qc = SqlPrepareQueryCampaign(BST_DB,
            "SELECT COUNT(*) FROM catalogue c" +
            " WHERE c.resref NOT IN (SELECT resref FROM kills WHERE uuid=@u)");
    if (nMode != 2) SqlBindString(qc, "@u", sUuid);
    int nTotal = 0;
    if (SqlStep(qc)) nTotal = SqlGetInt(qc, 0);
    SetLocalInt(oPC, "bst_page_total", nTotal);

    int nPages = (nTotal + 8) / 9;
    if (nPages == 0) nPages = 1;
    int nPage = nOff / 9 + 1;
    string sHeading = "Not Yet Slain";
    if (nMode == 0) sHeading = "Creatures Slain";
    else if (nMode == 2) sHeading = "Bosses Not Yet Slain  (" +
        IntToString(Bst_BossSlainCount(oPC)) + " of " + IntToString(Bst_BossTotal()) + " felled)";
    SetCustomToken(5040, sHeading);
    SetCustomToken(5041, "Page " + IntToString(nPage) + " of " + IntToString(nPages));

    int i;
    for (i = 0; i < 9; i++)
    {
        DeleteLocalString(oPC, "bst_slot_" + IntToString(i) + "_resref");
        SetCustomToken(5030 + i, "");
    }

    sqlquery q;
    if (nMode == 2)
        q = SqlPrepareQueryCampaign("respawndb",
            "SELECT resref, name, cr, area_name FROM boss_registry" + sBossWhere +
            " ORDER BY cr DESC, name ASC LIMIT 9 OFFSET @off");
    else if (nMode == 0)
        q = SqlPrepareQueryCampaign(BST_DB,
            "SELECT c.resref, c.name, c.cr, k.solo_kills, k.party_kills" +
            " FROM catalogue c JOIN kills k ON k.resref=c.resref" +
            " WHERE k.uuid=@u ORDER BY c.cr DESC, c.name ASC LIMIT 9 OFFSET @off");
    else
        q = SqlPrepareQueryCampaign(BST_DB,
            "SELECT c.resref, c.name, c.cr" +
            " FROM catalogue c WHERE c.resref NOT IN (SELECT resref FROM kills WHERE uuid=@u)" +
            " ORDER BY c.cr DESC, c.name ASC LIMIT 9 OFFSET @off");
    if (nMode != 2) SqlBindString(q, "@u", sUuid);
    SqlBindInt(q, "@off", nOff);

    i = 0;
    while (SqlStep(q) && i < 9)
    {
        string sResref = SqlGetString(q, 0);
        string sName   = SqlGetString(q, 1);
        int    nCR     = FloatToInt(SqlGetFloat(q, 2));

        SetLocalString(oPC, "bst_slot_" + IntToString(i) + "_resref", sResref);

        string sLabel;
        if (nMode == 2)
            sLabel = sName + "  (CR " + IntToString(nCR) + ")  - " + SqlGetString(q, 3);
        else if (nMode == 0)
            sLabel = sName + "  (CR " + IntToString(nCR) + ")  [Solo:"
                   + IntToString(SqlGetInt(q, 3)) + " Party:"
                   + IntToString(SqlGetInt(q, 4)) + "]";
        else
            sLabel = sName + "  (CR " + IntToString(nCR) + ")";

        SetCustomToken(5030 + i, sLabel);
        i++;
    }
}
