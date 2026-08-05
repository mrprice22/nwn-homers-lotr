// ru_db.nss - "Recent Updates" sign database helpers.
//
// Campaign DB "roadmapdb" (file database/roadmapdb.sqlite3), table
// recent_updates. Written by bin/roadmap_publish.py -- from the roadmap editor's
// "Publish to Wiki & DB" button, from bin/publish-roadmap-db.py, or from the
// nightly bin/refresh-homers-lotr-wiki run. In-game we only READ it.
//
//   bucket, rank (0 = newest within its bucket), title, prefix, group_label,
//   player, date, notes
//
// Two buckets, chosen from the sign's opening menu:
//   "shipped"  the 10 newest updates that are DONE and validated
//   "testing"  every update that has shipped but still has an open UAT step --
//              no cap, so this list can run to many pages. Its notes carry the
//              outstanding checks and which character can run them, because the
//              point of showing it to players is that they can help.
//
// Browsed 5-per-page in ru_sign.dlg (the Well of Eru sign). Custom tokens:
//   6200-6204 = list row labels        6205 = list header + "Page x of y"
//   6206      = menu: pending count    6210-6214 = drill-down detail fields
// Per-PC locals:
//   string "ru_bucket"    which bucket is being browsed ("" = shipped)
//   int    "ru_page_off"  row offset within the bucket
//   int    "ru_total"     total rows in the bucket (for [Next page] visibility)
//   int    "ru_slot_N_rank"  rank shown in list slot N (-1 = empty / hidden)

const string RU_DB      = "roadmapdb";
const string RU_SHIPPED = "shipped";
const string RU_TESTING = "testing";
const int    RU_PER_PAGE = 5;

void RU_InitDb()
{
    sqlquery q = SqlPrepareQueryCampaign(RU_DB,
        "CREATE TABLE IF NOT EXISTS recent_updates (" +
        "bucket TEXT NOT NULL DEFAULT 'shipped'," +
        "rank INTEGER NOT NULL," +
        "title TEXT," +
        "prefix TEXT," +
        "group_label TEXT," +
        "player TEXT," +
        "date TEXT," +
        "notes TEXT," +
        "PRIMARY KEY (bucket, rank))");
    SqlStep(q);
}

// Which list the PC is browsing. Defaults to the validated updates, so a PC who
// somehow reaches the list without passing the menu sees the old behaviour.
string RU_Bucket(object oPC)
{
    string sB = GetLocalString(oPC, "ru_bucket");
    return (sB == "") ? RU_SHIPPED : sB;
}

int RU_CountBucket(string sBucket)
{
    sqlquery q = SqlPrepareQueryCampaign(RU_DB,
        "SELECT COUNT(*) FROM recent_updates WHERE bucket=@b");
    SqlBindString(q, "@b", sBucket);
    return SqlStep(q) ? SqlGetInt(q, 0) : 0;
}

// Build the current list page: clears the 5 slots then fills them from the DB
// at the current offset, and records the total row count for pagination.
void RU_BuildPage(object oPC)
{
    string sBucket = RU_Bucket(oPC);
    int nOff   = GetLocalInt(oPC, "ru_page_off");
    int nTotal = RU_CountBucket(sBucket);
    SetLocalInt(oPC, "ru_total", nTotal);

    int i;
    for (i = 0; i < RU_PER_PAGE; i++)
    {
        SetLocalInt(oPC, "ru_slot_" + IntToString(i) + "_rank", -1);
        SetCustomToken(6200 + i, "");
    }

    sqlquery q = SqlPrepareQueryCampaign(RU_DB,
        "SELECT rank, prefix, title FROM recent_updates" +
        " WHERE bucket=@b ORDER BY rank ASC LIMIT 5 OFFSET @off");
    SqlBindString(q, "@b", sBucket);
    SqlBindInt(q, "@off", nOff);

    i = 0;
    while (SqlStep(q) && i < RU_PER_PAGE)
    {
        int    nRank   = SqlGetInt(q, 0);
        string sPrefix = SqlGetString(q, 1);
        string sTitle  = SqlGetString(q, 2);
        SetLocalInt(oPC, "ru_slot_" + IntToString(i) + "_rank", nRank);
        SetCustomToken(6200 + i, sPrefix + sTitle);
        i++;
    }

    // Header: which list this is, and where in it we are. The testing list runs
    // to many pages, so "Page x of y" is not decoration there.
    int nPages = (nTotal + RU_PER_PAGE - 1) / RU_PER_PAGE;
    if (nPages < 1) nPages = 1;
    int nPage = nOff / RU_PER_PAGE + 1;
    string sHead;
    if (sBucket == RU_TESTING)
        sHead = "These updates are LIVE but still need testing. Play them and "
              + "tell the admin what you find.";
    else
        sHead = "Recent updates to Middle-earth, tested and done.";
    if (nTotal == 0)
        sHead += "\n(Nothing here right now.)";
    else
        sHead += "\n" + IntToString(nTotal) + (nTotal == 1 ? " entry" : " entries")
               + ".  (Page " + IntToString(nPage) + " of " + IntToString(nPages) + ")";
    SetCustomToken(6205, sHead);
}

// Populate the drill-down detail tokens for one idea (by rank within a bucket).
void RU_BuildDetail(object oPC, int nRank)
{
    SetCustomToken(6210, "");
    SetCustomToken(6211, "");
    SetCustomToken(6212, "");
    SetCustomToken(6213, "");
    SetCustomToken(6214, "");

    sqlquery q = SqlPrepareQueryCampaign(RU_DB,
        "SELECT title, prefix, group_label, player, date, notes" +
        " FROM recent_updates WHERE bucket=@b AND rank=@r");
    SqlBindString(q, "@b", RU_Bucket(oPC));
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

// Opening menu: reset the browse state and label the "needs testing" branch with
// its live count, so a player can see at a glance whether there is work to do.
void RU_BuildMenu(object oPC)
{
    DeleteLocalString(oPC, "ru_bucket");
    SetLocalInt(oPC, "ru_page_off", 0);
    int nPending = RU_CountBucket(RU_TESTING);
    SetCustomToken(6206, IntToString(nPending));
}

// Enter one of the two lists from the menu.
void RU_OpenBucket(object oPC, string sBucket)
{
    SetLocalString(oPC, "ru_bucket", sBucket);
    SetLocalInt(oPC, "ru_page_off", 0);
    RU_BuildPage(oPC);
}
