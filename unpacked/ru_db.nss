// ru_db.nss — "Recent Updates" sign database helpers.
//
// Campaign DB "roadmapdb" (file database/roadmapdb.sqlite3), table recent_updates.
// The table is written by bin/roadmap-editor.py on the "Publish to Wiki & DB"
// button: the 10 most recently shipped roadmap ideas (status implemented/awarded)
// by date desc. In-game we only READ it.
//
//   rank 0..9 (0 = newest), title, prefix, group_label, player, date, notes
//
// Browsed 5-per-page in ru_sign.dlg (the Well of Eru sign). Custom tokens:
//   6200-6204 = list row labels   6210-6214 = drill-down detail fields
// Per-PC locals:
//   int "ru_page_off"     row offset (0 or 5)
//   int "ru_total"        total rows (for [Next page] visibility)
//   int "ru_slot_N_rank"  rank shown in list slot N (-1 = empty / hidden)

const string RU_DB = "roadmapdb";

void RU_InitDb()
{
    sqlquery q = SqlPrepareQueryCampaign(RU_DB,
        "CREATE TABLE IF NOT EXISTS recent_updates (" +
        "rank INTEGER PRIMARY KEY," +
        "title TEXT," +
        "prefix TEXT," +
        "group_label TEXT," +
        "player TEXT," +
        "date TEXT," +
        "notes TEXT)");
    SqlStep(q);
}

// Build the current list page: clears the 5 slots then fills them from the DB
// at the current offset, and records the total row count for pagination.
void RU_BuildPage(object oPC)
{
    int nOff = GetLocalInt(oPC, "ru_page_off");

    sqlquery qc = SqlPrepareQueryCampaign(RU_DB,
        "SELECT COUNT(*) FROM recent_updates");
    int nTotal = 0;
    if (SqlStep(qc)) nTotal = SqlGetInt(qc, 0);
    SetLocalInt(oPC, "ru_total", nTotal);

    int i;
    for (i = 0; i < 5; i++)
    {
        SetLocalInt(oPC, "ru_slot_" + IntToString(i) + "_rank", -1);
        SetCustomToken(6200 + i, "");
    }

    sqlquery q = SqlPrepareQueryCampaign(RU_DB,
        "SELECT rank, prefix, title FROM recent_updates" +
        " ORDER BY rank ASC LIMIT 5 OFFSET @off");
    SqlBindInt(q, "@off", nOff);

    i = 0;
    while (SqlStep(q) && i < 5)
    {
        int    nRank   = SqlGetInt(q, 0);
        string sPrefix = SqlGetString(q, 1);
        string sTitle  = SqlGetString(q, 2);
        SetLocalInt(oPC, "ru_slot_" + IntToString(i) + "_rank", nRank);
        SetCustomToken(6200 + i, sPrefix + sTitle);
        i++;
    }
}

// Populate the drill-down detail tokens for one idea (by rank).
void RU_BuildDetail(object oPC, int nRank)
{
    SetCustomToken(6210, "");
    SetCustomToken(6211, "");
    SetCustomToken(6212, "");
    SetCustomToken(6213, "");
    SetCustomToken(6214, "");

    sqlquery q = SqlPrepareQueryCampaign(RU_DB,
        "SELECT title, prefix, group_label, player, date, notes" +
        " FROM recent_updates WHERE rank=@r");
    SqlBindInt(q, "@r", nRank);
    if (!SqlStep(q)) return;

    string sTitle  = SqlGetString(q, 0);
    string sPrefix = SqlGetString(q, 1);
    SetCustomToken(6210, sPrefix + sTitle);
    SetCustomToken(6211, SqlGetString(q, 2));
    SetCustomToken(6212, SqlGetString(q, 3));
    SetCustomToken(6213, SqlGetString(q, 4));

    string sNotes = SqlGetString(q, 5);
    if (sNotes == "") sNotes = "(No further details recorded.)";
    SetCustomToken(6214, sNotes);
}
