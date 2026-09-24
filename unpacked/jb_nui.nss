// jb_nui.nss - the player jukebox's song browser.
//
// Opened from the placeable (jb_plc_used). Event handling is in jb_evt.nss,
// registered per-window via NuiCreate's sEventScript - this module has no
// central NUI dispatcher, every window carries its own handler.
//
// WHY A WINDOW AND NOT THE CONVERSATION
//
// The admin jukebox's jb_conv lists 8 tracks a page on custom tokens 7010-7018
// and knows only our 5 custom songs. The player catalogue is 113 tracks
// (jb_catalog.nss), which is 15 pages of dialogue to walk with no way to search
// and no way to sort. A window can do both.
//
// THE LIST COMES FROM SQL, NOT FROM THE CATALOGUE TABLE. jb_plays carries each
// track's name beside its play count, so one statement does the filtering, the
// ordering and the paging. "Sort by most played" is the reason: NWScript has no
// array, so there is nothing to sort 113 entries in. The catalogue is still the
// source of the names, durations and rows - jb_db seeds jb_plays from it.
//
// SHAPE, and the traps it is built around - all four recorded against this
// repo's other NUI windows, see csp_nui.nss:18-34:
//
//   * EVERY child gets an explicit width and the list group an explicit size.
//     Otherwise the group sizes to its longest label, grows a horizontal
//     scrollbar and clips the header.
//   * Nothing long goes in a TOOLTIP. A NUI tooltip renders one line, never
//     clips it, and silently strips newlines. Track names are bounded by the
//     name column, so the tooltips here are short by construction.
//   * Too many widgets in one window fails outright with "Error constructing
//     window from json". dye_nui_inc caps at 48 cells for this reason, so the
//     list is PAGED at JB_NUI_PAGE rows rather than rendering all 113.
//   * The window is REBUILT rather than updated after an action, which is the
//     house convention (legfeat_nui, csp_nui).
//
// WHY SEARCH IS A BUTTON AND NOT LIVE FILTERING
//
// A watched bind fires on every keystroke, and the only way to change the row
// set is to rebuild the window - which destroys and recreates it, taking the
// keyboard focus out of the text field. Live filtering would therefore accept
// exactly one character and then drop focus. The field is read on demand
// instead, when Search is clicked.
#include "nw_inc_nui"
#include "jb_db"
#include "color"

const string JB_WIN      = "jukebox";
const string JB_NUI_TOK  = "JB_NUI_TOK";    // PC local: this window's token
const string JB_NUI_PG   = "JB_NUI_PG";     // PC local: current page, 0-based
const string JB_NUI_Q    = "JB_NUI_Q";      // PC local: the active search term
const string JB_NUI_SORT = "JB_NUI_SORT";   // PC local: "" (A-Z) or "plays"
const string JB_NUI_TIER = "JB_NUI_TIER";   // PC local: chosen priority tier

const string JB_BIND_SEARCH = "jb_search";

const int JB_NUI_PAGE = 12;                 // rows per page; see widget cap above

const float JB_WIN_W    = 560.0;
const float JB_WIN_H    = 580.0;
const float JB_LIST_W   = 510.0;
const float JB_LIST_H   = 300.0;
const float JB_COL_BTN  = 80.0;
const float JB_COL_NAME = 270.0;
const float JB_COL_LEN  = 60.0;
const float JB_COL_PLAY = 80.0;
const float JB_ROW_H    = 30.0;

void JB_NuiOpen(object oPC);
void JB_NuiClose(object oPC);

// ------------------------------------------------------------------- state --

string JB_Query(object oPC) { return GetLocalString(oPC, JB_NUI_Q); }
string JB_Sort(object oPC)  { return GetLocalString(oPC, JB_NUI_SORT); }
int    JB_Tier(object oPC)  { return GetLocalInt(oPC, JB_NUI_TIER); }

int JB_PageCount(object oPC)
{
    int nTotal = JB_ListCount(JB_Query(oPC));
    if (nTotal <= 0) return 1;
    return (nTotal + JB_NUI_PAGE - 1) / JB_NUI_PAGE;
}

int JB_Page(object oPC)
{
    int nPage = GetLocalInt(oPC, JB_NUI_PG);
    int nMax  = JB_PageCount(oPC) - 1;
    if (nPage < 0) nPage = 0;
    if (nPage > nMax) nPage = nMax;
    return nPage;
}

// ------------------------------------------------------------------ layout --

// "4:31" - a length a player can weigh before spending on it. Stock tracks run
// from 19 seconds to over ten minutes, so this is not decoration: it is how
// long the room is committed for.
string JB_LenStr(int nSeconds)
{
    int nMin = nSeconds / 60;
    int nSec = nSeconds % 60;
    return IntToString(nMin) + ":" + (nSec < 10 ? "0" : "") + IntToString(nSec);
}

// The catalogue index for a raw 2DA row, or -1. The queue and jb_plays both
// speak in rows, because a row is what the engine plays and what an area
// stores; the catalogue index is only a position in a generated table.
int JB_CatIndexForRow(int nRow)
{
    int i;
    for (i = 0; i < JB_CatCount(); i++)
        if (JB_CatRow(i) == nRow) return i;
    return -1;
}

// One list entry: a Queue button (id "q<raw row>"), the name, length, plays.
json JB_Row(object oPC, int nRow, int nPlayingRow, int nGold)
{
    int nCat = JB_CatIndexForRow(nRow);
    if (nCat < 0) return JsonNull();

    int bPlaying = (nRow == nPlayingRow);
    int nCost = JB_TierCost(JB_Tier(oPC));

    json jRow = JsonArray();

    json jBtn = NuiId(NuiButton(JsonString(bPlaying ? "Playing" : "Queue")),
                      "q" + IntToString(nRow));
    // Greyed, never hidden, when it is already playing or the player cannot
    // afford the chosen tier - so the whole list stays readable and a player can
    // see what they are saving up for. jb_evt re-checks the gold before taking
    // it; this window is only a snapshot of it.
    jBtn = NuiEnabled(jBtn, JsonBool(!bPlaying && nGold >= nCost));
    jBtn = NuiTooltip(jBtn, JsonString(bPlaying
        ? "The room is playing this now"
        : "Queue this for " + JB_Gold(nCost) + " gp"));
    jRow = JsonArrayInsert(jRow, NuiWidth(jBtn, JB_COL_BTN));

    json jName = NuiLabel(JsonString(JB_CatName(nCat)),
                          JsonInt(NUI_HALIGN_LEFT), JsonInt(NUI_VALIGN_MIDDLE));
    jName = NuiTooltip(jName, JsonString(JB_CatName(nCat)));
    jRow = JsonArrayInsert(jRow, NuiWidth(jName, JB_COL_NAME));

    json jLen = NuiLabel(JsonString(JB_LenStr(JB_CatDuration(nCat))),
                         JsonInt(NUI_HALIGN_RIGHT), JsonInt(NUI_VALIGN_MIDDLE));
    jRow = JsonArrayInsert(jRow, NuiWidth(jLen, JB_COL_LEN));

    int nPlays = JB_PlaysFor(nRow);
    json jPlays = NuiLabel(JsonString(nPlays == 0 ? "-" : IntToString(nPlays)),
                           JsonInt(NUI_HALIGN_RIGHT), JsonInt(NUI_VALIGN_MIDDLE));
    jPlays = NuiTooltip(jPlays, JsonString(nPlays == 1
        ? "Played once here" : "Played " + IntToString(nPlays) + " times here"));
    jRow = JsonArrayInsert(jRow, NuiWidth(jPlays, JB_COL_PLAY));

    return NuiHeight(NuiRow(jRow), JB_ROW_H);
}

// What the room is playing and what is waiting. The jukebox is area-wide by
// design, so this is the state of the ROOM, not of the player reading it.
string JB_StatusLine(object oArea, object oPC)
{
    string sNow;
    if (GetLocalInt(oArea, JB_ON))
    {
        int nCat = JB_CatIndexForRow(GetLocalInt(oArea, JB_ROW));
        // A row the catalogue does not carry means the admin item is playing one
        // of the excluded rows. Say something true rather than an empty name.
        sNow = "Now playing: " + ((nCat >= 0) ? JB_CatName(nCat) : "an unlisted track");
    }
    else
        sNow = "Silent. The room is playing its own music.";

    int nWaiting = JB_QueueLength(oArea);
    if (nWaiting > 0)
        sNow += "   " + IntToString(nWaiting) + " waiting.";

    return sNow;
}

json JB_Window(object oPC)
{
    object oArea = GetArea(oPC);
    int nPlayingRow = GetLocalInt(oArea, JB_ON) ? GetLocalInt(oArea, JB_ROW) : -1;
    int nGold = GetGold(oPC);
    int nTier = JB_Tier(oPC);

    json jCol = JsonArray();

    // Status. A text widget rather than a label: the line carries a track name
    // of unbounded length and a label would drop the tail with no visual cue.
    jCol = JsonArrayInsert(jCol, NuiHeight(NuiWidth(
        NuiText(JsonString(JB_StatusLine(oArea, oPC)), FALSE, NUI_SCROLLBARS_NONE),
        JB_LIST_W), 40.0));

    // Search row. The term lives on the PC, not in the widget, so a rebuilt
    // window comes back agreeing with the list it is filtering.
    json jSearch = JsonArray();
    jSearch = JsonArrayInsert(jSearch, NuiWidth(
        NuiId(NuiTextEdit(JsonString("Search by name"), NuiBind(JB_BIND_SEARCH),
                          64, FALSE), "qedit"), 250.0));
    jSearch = JsonArrayInsert(jSearch, NuiWidth(
        NuiId(NuiButton(JsonString("Search")), "bfind"), 80.0));
    jSearch = JsonArrayInsert(jSearch, NuiWidth(
        NuiId(NuiButton(JsonString("All")), "ball"), 60.0));
    json jSort = NuiId(NuiButton(JsonString(
        JB_Sort(oPC) == "plays" ? "Most played" : "A-Z")), "bsort");
    jSort = NuiTooltip(jSort, JsonString("Switch between A-Z and most played"));
    jSearch = JsonArrayInsert(jSearch, NuiWidth(jSort, 110.0));
    jCol = JsonArrayInsert(jCol, NuiHeight(NuiRow(jSearch), 32.0));

    // Priority row. One button that cycles the tier, rather than a control per
    // tier on every row - five tiers times twelve rows would be sixty extra
    // widgets for a choice that is made once.
    json jPrio = JsonArray();
    json jTier = NuiId(NuiButton(JsonString(
        "Priority: " + JB_TierName(nTier) + " - " + JB_Gold(JB_TierCost(nTier))
        + " gp")), "btier");
    jTier = NuiTooltip(jTier, JsonString(
        "Click to change how far ahead you pay to jump"));
    jPrio = JsonArrayInsert(jPrio, NuiWidth(jTier, 330.0));

    int nAhead = JB_AheadOf(oArea, nTier);
    string sAhead = (nAhead == 0)
        ? "Nothing outranks this"
        : IntToString(nAhead) + " ahead of you";
    jPrio = JsonArrayInsert(jPrio, NuiWidth(
        NuiLabel(JsonString(sAhead), JsonInt(NUI_HALIGN_LEFT),
                 JsonInt(NUI_VALIGN_MIDDLE)), 170.0));
    jCol = JsonArrayInsert(jCol, NuiHeight(NuiRow(jPrio), 32.0));

    // The list. Explicitly sized, vertical scrollbars only, and PAGED - see the
    // widget cap in the header.
    int nPage = JB_Page(oPC);
    int nFrom = nPage * JB_NUI_PAGE;
    string sQ = JB_Query(oPC);
    string sSort = JB_Sort(oPC);

    json jList = JsonArray();
    int i;
    for (i = 0; i < JB_NUI_PAGE; i++)
    {
        int nRow = JB_ListRowAt(sQ, sSort, nFrom + i);
        if (nRow < 0) break;
        json jEntry = JB_Row(oPC, nRow, nPlayingRow, nGold);
        if (JsonGetType(jEntry) != JSON_TYPE_NULL)
            jList = JsonArrayInsert(jList, jEntry);
    }
    if (JsonGetLength(jList) == 0)
        jList = JsonArrayInsert(jList, NuiHeight(NuiWidth(
            NuiLabel(JsonString("Nothing by that name."),
                     JsonInt(NUI_HALIGN_CENTER), JsonInt(NUI_VALIGN_MIDDLE)),
            JB_LIST_W), JB_ROW_H));

    json jGroup = NuiGroup(NuiCol(jList), TRUE, NUI_SCROLLBARS_Y);
    jGroup = NuiWidth(jGroup, JB_LIST_W);
    jGroup = NuiHeight(jGroup, JB_LIST_H);
    jCol = JsonArrayInsert(jCol, jGroup);

    // Paging, purse, and the way out.
    json jFoot = JsonArray();
    json jPrev = NuiId(NuiButton(JsonString("< Prev")), "bprev");
    jPrev = NuiEnabled(jPrev, JsonBool(nPage > 0));
    jFoot = JsonArrayInsert(jFoot, NuiWidth(jPrev, 75.0));

    jFoot = JsonArrayInsert(jFoot, NuiWidth(
        NuiLabel(JsonString("page " + IntToString(nPage + 1) + " of "
                            + IntToString(JB_PageCount(oPC))),
                 JsonInt(NUI_HALIGN_CENTER), JsonInt(NUI_VALIGN_MIDDLE)), 100.0));

    json jNext = NuiId(NuiButton(JsonString("Next >")), "bnext");
    jNext = NuiEnabled(jNext, JsonBool(nPage + 1 < JB_PageCount(oPC)));
    jFoot = JsonArrayInsert(jFoot, NuiWidth(jNext, 75.0));

    jFoot = JsonArrayInsert(jFoot, NuiWidth(
        NuiLabel(JsonString(JB_Gold(nGold) + " gp"), JsonInt(NUI_HALIGN_RIGHT),
                 JsonInt(NUI_VALIGN_MIDDLE)), 180.0));

    jFoot = JsonArrayInsert(jFoot, NuiWidth(
        NuiId(NuiButton(JsonString("Close")), "bclose"), 75.0));
    jCol = JsonArrayInsert(jCol, NuiHeight(NuiRow(jFoot), 32.0));

    return NuiWindow(NuiCol(jCol), JsonString("Jukebox"),
        NuiRect(-1.0, -1.0, JB_WIN_W, JB_WIN_H),
        JsonBool(FALSE),   // resizable
        JsonBool(FALSE),   // collapsed
        JsonBool(TRUE),    // closable
        JsonBool(FALSE),   // transparent
        JsonBool(TRUE));   // border
}

// ----------------------------------------------------------------- open it --

void JB_NuiClose(object oPC)
{
    int nTok = GetLocalInt(oPC, JB_NUI_TOK);
    if (nTok) NuiDestroy(oPC, nTok);
    DeleteLocalInt(oPC, JB_NUI_TOK);
    // The next time anyone opens it they start on page one with no filter,
    // rather than wherever the last visit left off. The chosen tier is kept:
    // it is a spending decision, not a view.
    DeleteLocalInt(oPC, JB_NUI_PG);
    DeleteLocalString(oPC, JB_NUI_Q);
    DeleteLocalString(oPC, JB_NUI_SORT);
}

// Open, or rebuild in place. Destroying any stale instance first is how the
// list refreshes after an action, exactly as legfeat_nui does.
void JB_NuiOpen(object oPC)
{
    if (!GetIsPC(oPC)) return;

    int nOld = NuiFindWindow(oPC, JB_WIN);
    if (nOld) NuiDestroy(oPC, nOld);

    int nTok = NuiCreate(oPC, JB_Window(oPC), JB_WIN, "jb_evt");
    SetLocalInt(oPC, JB_NUI_TOK, nTok);

    // Put the active term back in the field after a rebuild, so the box always
    // agrees with the list it filtered.
    NuiSetBind(oPC, nTok, JB_BIND_SEARCH, JsonString(JB_Query(oPC)));
}
