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
// (jb_catalog.nss), which is 15 pages of dialogue to walk and no way to search.
// A window can filter.
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
// instead, when Search (or Enter-equivalent) is clicked.
#include "nw_inc_nui"
#include "jb_catalog"
#include "jb_inc"

const string JB_WIN      = "jukebox";
const string JB_NUI_TOK  = "JB_NUI_TOK";    // PC local: this window's token
const string JB_NUI_PG   = "JB_NUI_PG";     // PC local: current page, 0-based
const string JB_NUI_Q    = "JB_NUI_Q";      // PC local: the active search term

const string JB_BIND_SEARCH = "jb_search";

const int JB_NUI_PAGE = 15;                 // rows per page; see widget cap above

const float JB_WIN_W    = 520.0;
const float JB_WIN_H    = 560.0;
const float JB_LIST_W   = 470.0;
const float JB_LIST_H   = 330.0;
const float JB_COL_BTN  = 70.0;
const float JB_COL_NAME = 300.0;
const float JB_COL_LEN  = 80.0;
const float JB_ROW_H    = 30.0;
const float JB_HDR_H    = 26.0;

void JB_NuiOpen(object oPC);
void JB_NuiClose(object oPC);

// ------------------------------------------------------------------ filter --

// Does the track at catalogue index nIndex match the PC's current search term?
// Case-insensitive substring over the name. An empty term matches everything.
int JB_Matches(object oPC, int nIndex)
{
    string sQ = GetLocalString(oPC, JB_NUI_Q);
    if (sQ == "") return TRUE;
    return FindSubString(GetStringLowerCase(JB_CatName(nIndex)),
                         GetStringLowerCase(sQ)) >= 0;
}

// How many tracks the current search matches.
int JB_MatchCount(object oPC)
{
    int i, n = 0;
    for (i = 0; i < JB_CatCount(); i++)
        if (JB_Matches(oPC, JB_CatByName(i))) n++;
    return n;
}

// The catalogue index of the nth MATCHING track in alphabetical order, or -1.
//
// Walked rather than indexed because a filtered list has no closed form and
// NWScript has no array to cache one in. 113 entries is small enough that the
// walk is cheaper than any structure that would avoid it.
int JB_MatchAt(object oPC, int nWanted)
{
    int i, n = 0;
    for (i = 0; i < JB_CatCount(); i++)
    {
        int nIndex = JB_CatByName(i);
        if (!JB_Matches(oPC, nIndex)) continue;
        if (n == nWanted) return nIndex;
        n++;
    }
    return -1;
}

int JB_PageCount(object oPC)
{
    int nTotal = JB_MatchCount(oPC);
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
// from 19 seconds to over ten minutes, so this is not decoration.
string JB_LenStr(int nSeconds)
{
    int nMin = nSeconds / 60;
    int nSec = nSeconds % 60;
    return IntToString(nMin) + ":" + (nSec < 10 ? "0" : "") + IntToString(nSec);
}

// One list entry: a Play button (id "p<catalogue index>"), the name, the length.
json JB_Row(object oPC, int nIndex, int nPlayingRow)
{
    int bPlaying = (JB_CatRow(nIndex) == nPlayingRow);

    json jRow = JsonArray();

    json jBtn = NuiId(NuiButton(JsonString(bPlaying ? "Playing" : "Play")),
                      "p" + IntToString(nIndex));
    // Greyed, not hidden, for the track already playing - the player can still
    // see where it is in the list. Every other row stays enabled; the action
    // script is what actually decides, this window is only a snapshot.
    jBtn = NuiEnabled(jBtn, JsonBool(!bPlaying));
    jBtn = NuiTooltip(jBtn, JsonString(bPlaying
        ? "This is what the room is playing now"
        : "Play this in the room"));
    jRow = JsonArrayInsert(jRow, NuiWidth(jBtn, JB_COL_BTN));

    json jName = NuiLabel(JsonString(JB_CatName(nIndex)),
                          JsonInt(NUI_HALIGN_LEFT), JsonInt(NUI_VALIGN_MIDDLE));
    jName = NuiTooltip(jName, JsonString(JB_CatName(nIndex)));
    jRow = JsonArrayInsert(jRow, NuiWidth(jName, JB_COL_NAME));

    json jLen = NuiLabel(JsonString(JB_LenStr(JB_CatDuration(nIndex))),
                         JsonInt(NUI_HALIGN_RIGHT), JsonInt(NUI_VALIGN_MIDDLE));
    jRow = JsonArrayInsert(jRow, NuiWidth(jLen, JB_COL_LEN));

    return NuiHeight(NuiRow(jRow), JB_ROW_H);
}

// The catalogue index playing raw 2DA row nRow, or -1. The area records a ROW
// (JB_ROW), not a catalogue index, because the same room can be driven by the
// admin item's own table as well as by this window.
int JB_CatIndexForRow(int nRow)
{
    int i;
    for (i = 0; i < JB_CatCount(); i++)
        if (JB_CatRow(i) == nRow) return i;
    return -1;
}

// What the room is playing, in words. JB_ON/JB_ROW are area locals owned by
// jb_inc.nss; the jukebox is area-wide by design, so this is the state of the
// ROOM, not of the player reading it.
string JB_StatusLine(object oArea, object oPC)
{
    int nTotal = JB_MatchCount(oPC);
    string sQ = GetLocalString(oPC, JB_NUI_Q);

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

    string sFound = IntToString(nTotal) + " track" + (nTotal == 1 ? "" : "s");
    if (sQ != "") sFound += " matching \"" + sQ + "\"";

    return sNow + "   (" + sFound + ")";
}

json JB_Window(object oPC)
{
    object oArea = GetArea(oPC);
    int nPlayingRow = GetLocalInt(oArea, JB_ON)
                    ? GetLocalInt(oArea, JB_ROW) : -1;

    json jCol = JsonArray();

    // Status. A text widget rather than a label: the line carries a track name
    // of unbounded length and a label would drop the tail with no visual cue.
    jCol = JsonArrayInsert(jCol, NuiHeight(NuiWidth(
        NuiText(JsonString(JB_StatusLine(oArea, oPC)), FALSE, NUI_SCROLLBARS_NONE),
        JB_LIST_W), 44.0));

    // Search row. The field holds its term across rebuilds because the term
    // lives on the PC, not in the widget - a rebuilt window starts with an
    // empty field otherwise, and the list it is filtering would disagree with it.
    json jSearch = JsonArray();
    json jEdit = NuiId(NuiTextEdit(JsonString("Search by name"),
                                   NuiBind(JB_BIND_SEARCH), 64, FALSE),
                       "qedit");
    jSearch = JsonArrayInsert(jSearch, NuiWidth(jEdit, 300.0));
    jSearch = JsonArrayInsert(jSearch, NuiWidth(
        NuiId(NuiButton(JsonString("Search")), "bfind"), 80.0));
    jSearch = JsonArrayInsert(jSearch, NuiWidth(
        NuiId(NuiButton(JsonString("All")), "ball"), 70.0));
    jCol = JsonArrayInsert(jCol, NuiHeight(NuiRow(jSearch), JB_HDR_H + 6.0));

    // The list. Explicitly sized, vertical scrollbars only, and PAGED - see the
    // widget cap in the header.
    int nPage = JB_Page(oPC);
    int nFrom = nPage * JB_NUI_PAGE;
    json jList = JsonArray();
    int i;
    for (i = 0; i < JB_NUI_PAGE; i++)
    {
        int nIndex = JB_MatchAt(oPC, nFrom + i);
        if (nIndex < 0) break;
        jList = JsonArrayInsert(jList, JB_Row(oPC, nIndex, nPlayingRow));
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

    // Paging and the stop control.
    json jFoot = JsonArray();
    json jPrev = NuiId(NuiButton(JsonString("< Prev")), "bprev");
    jPrev = NuiEnabled(jPrev, JsonBool(nPage > 0));
    jFoot = JsonArrayInsert(jFoot, NuiWidth(jPrev, 80.0));

    jFoot = JsonArrayInsert(jFoot, NuiWidth(
        NuiLabel(JsonString("page " + IntToString(nPage + 1) + " of "
                            + IntToString(JB_PageCount(oPC))),
                 JsonInt(NUI_HALIGN_CENTER), JsonInt(NUI_VALIGN_MIDDLE)), 110.0));

    json jNext = NuiId(NuiButton(JsonString("Next >")), "bnext");
    jNext = NuiEnabled(jNext, JsonBool(nPage + 1 < JB_PageCount(oPC)));
    jFoot = JsonArrayInsert(jFoot, NuiWidth(jNext, 80.0));

    json jStop = NuiId(NuiButton(JsonString("Stop")), "bstop");
    jStop = NuiEnabled(jStop, JsonBool(GetLocalInt(oArea, JB_ON)));
    jStop = NuiTooltip(jStop, JsonString("Give the room its own music back"));
    jFoot = JsonArrayInsert(jFoot, NuiWidth(jStop, 80.0));

    jFoot = JsonArrayInsert(jFoot, NuiWidth(
        NuiId(NuiButton(JsonString("Close")), "bclose"), 80.0));
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
    // The next player to walk up starts on page one with no filter, rather than
    // wherever the last one left off.
    DeleteLocalInt(oPC, JB_NUI_PG);
    DeleteLocalString(oPC, JB_NUI_Q);
}

// Open, or rebuild in place. Destroying any stale instance first is how the
// list refreshes after a pick, exactly as legfeat_nui does.
void JB_NuiOpen(object oPC)
{
    if (!GetIsPC(oPC)) return;

    int nOld = NuiFindWindow(oPC, JB_WIN);
    if (nOld) NuiDestroy(oPC, nOld);

    int nTok = NuiCreate(oPC, JB_Window(oPC), JB_WIN, "jb_evt");
    SetLocalInt(oPC, JB_NUI_TOK, nTok);

    // Put the active term back in the field after a rebuild, so the box agrees
    // with the list it filtered.
    NuiSetBind(oPC, nTok, JB_BIND_SEARCH,
               JsonString(GetLocalString(oPC, JB_NUI_Q)));
}
