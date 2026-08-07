// csp_nui.nss - the caster spell picker window ("Spellbook Study").
//
// Opened right after a level-up past class level 40 (csp_lvl -> csp_open) and
// re-openable by finishing a rest while picks remain (on_mod_rest), which is
// the recovery path for a window that was dismissed. Event handling is in
// csp_evt.nss, registered per-window via NuiCreate's sEventScript.
//
// WHY A CUSTOM WINDOW AT ALL: see the header of csp_inc.nss. The client's own
// spell page is unreachable past class level 40.
//
// SHAPE. One spell level at a time, chosen with the row of buttons under the
// header, because 179 wizard-learnable spells in one list is unreadable and
// slow to build. The selected level is a local int on the PC (CSP_SEL, stored
// +1 so that "level 0" is distinguishable from "not set").
//
// The window is REBUILT rather than updated after each pick, exactly as
// legfeat_nui does: a learned spell leaves the list and the header count drops.
//
// Two traps recorded against this repo's other NUI windows apply here: resrefs
// are capped at 16 characters, and nw_inc_nui has no `&` reference parameters.
// Both are respected. A third, learned from the Legendary Feats picker: EVERY
// child gets an explicit width and the list group an explicit size, or the
// group sizes itself to its longest label, grows a horizontal scrollbar and
// clips the header text.

// A fourth, learned from legendary-nui-wrapping: a NUI tooltip renders its
// string as ONE line and never clips it, so a long one draws off the edge of
// the screen. The spell descriptions this window hangs off its rows are the
// longest strings either picker shows - they come straight from the TLK - so
// every one of them goes through NuiWrapText before it is attached.

#include "nw_inc_nui"
#include "nui_wrap_inc"
#include "csp_inc"

const string CSP_WIN = "cspells";      // NuiCreate window id
const string CSP_TOK = "CSP_TOK";      // PC local: this window's token
const string CSP_SEL = "CSP_SEL";      // PC local: selected spell level, +1

const float CSP_WIN_W    = 720.0;
const float CSP_WIN_H    = 500.0;
const float CSP_LIST_W   = 680.0;
const float CSP_LIST_H   = 300.0;
const float CSP_COL_BTN  = 80.0;
const float CSP_COL_NAME = 260.0;
const float CSP_COL_SCH  = 160.0;
const float CSP_ROW_H    = 30.0;
const float CSP_HDR_H    = 26.0;
const float CSP_TAB_W    = 64.0;

json CSP_Window(object oPC);
void CSP_Open(object oPC);
void CSP_Close(object oPC);

// Which spell level the window is showing. Defaults to the highest the
// character can use, which is the one a level-41+ wizard almost always wants.
int CSP_Selected(object oPC)
{
    int nSel = GetLocalInt(oPC, CSP_SEL) - 1;
    if (nSel >= 0 && CSP_CanUseSpellLevel(oPC, nSel)) return nSel;

    int nMax = CSP_MaxSpellLevel(oPC);
    return (nMax >= 0) ? nMax : 0;
}

// One spell row: a Learn button, the name, and the school.
json CSP_Row(object oPC, int nSpellId, int nRemaining)
{
    string sName = CSP_SpellName(nSpellId);
    string sTip  = CSP_SpellDesc(nSpellId);
    if (sTip == "") sTip = sName;
    // Wrapped, not truncated: a TLK spell description is hundreds of characters
    // and a tooltip will happily draw every one of them on a single line, past
    // the window and past the viewport. NuiWrapText keeps the newlines the TLK
    // text already carries and wraps the long lines between them.
    sTip = NuiWrapText(sTip, NUI_WRAP_COLS);

    json jRow = JsonArray();

    json jBtn = NuiId(NuiButton(JsonString("Learn")), "s" + IntToString(nSpellId));
    // Greyed rather than hidden with no picks left, so the player can still
    // read the whole list and plan. CSP_Learn re-checks everything.
    jBtn = NuiEnabled(jBtn, JsonBool(nRemaining > 0));
    jBtn = NuiTooltip(jBtn, JsonString(sTip));
    jRow = JsonArrayInsert(jRow, NuiWidth(jBtn, CSP_COL_BTN));

    json jName = NuiLabel(JsonString(sName), JsonInt(NUI_HALIGN_LEFT),
                          JsonInt(NUI_VALIGN_MIDDLE));
    jName = NuiTooltip(jName, JsonString(sTip));
    jRow = JsonArrayInsert(jRow, NuiWidth(jName, CSP_COL_NAME));

    json jSch = NuiLabel(JsonString(CSP_SchoolName(nSpellId)),
                         JsonInt(NUI_HALIGN_LEFT), JsonInt(NUI_VALIGN_MIDDLE));
    jSch = NuiTooltip(jSch, JsonString(sTip));
    jRow = JsonArrayInsert(jRow, NuiWidth(jSch, CSP_COL_SCH));

    return NuiHeight(NuiRow(jRow), CSP_ROW_H);
}

// The spell-level selector. A level the character cannot use at all is greyed;
// the one being shown is greyed too, so the row doubles as the "you are here".
json CSP_Tabs(object oPC, int nSel)
{
    json jRow = JsonArray();
    int i;
    for (i = 0; i <= 9; i++)
    {
        string sTxt = (i == 0) ? "Cantrip" : ("Lvl " + IntToString(i));
        json jBtn = NuiId(NuiButton(JsonString(sTxt)), "l" + IntToString(i));
        jBtn = NuiEnabled(jBtn, JsonBool(i != nSel && CSP_CanUseSpellLevel(oPC, i)));
        jRow = JsonArrayInsert(jRow, NuiWidth(jBtn, CSP_TAB_W));
    }
    return NuiHeight(NuiRow(jRow), CSP_ROW_H);
}

json CSP_Window(object oPC)
{
    int nRemaining = CSP_Remaining(oPC);
    int nSel = CSP_Selected(oPC);

    json jCol = JsonArray();

    string sHdr;
    if (nRemaining > 0)
        sHdr = "You may learn " + IntToString(nRemaining) + " new spell"
             + ((nRemaining == 1) ? "." : "s.");
    else
        sHdr = "You have no spells left to learn for now.";

    jCol = JsonArrayInsert(jCol, NuiHeight(NuiWidth(
        NuiLabel(JsonString(sHdr), JsonInt(NUI_HALIGN_CENTER),
                 JsonInt(NUI_VALIGN_MIDDLE)), CSP_LIST_W), CSP_HDR_H));

    jCol = JsonArrayInsert(jCol, CSP_Tabs(oPC, nSel));

    // One pass over spells.2da at the selected level. Rows the character
    // already knows, cannot cast, or is barred from by its specialisation are
    // filtered by CSP_IsOffered and never reach the list.
    int nRows = Get2DARowCount("spells");
    if (nRows <= 0 || nRows > CSP_MAX_SPELL_ROWS) nRows = CSP_MAX_SPELL_ROWS;

    json jList = JsonArray();
    int nShown = 0;
    int i;
    for (i = 0; i < nRows; i++)
    {
        if (CSP_SpellLevelOf(i) != nSel) continue;
        if (!CSP_IsOffered(oPC, i)) continue;
        jList = JsonArrayInsert(jList, CSP_Row(oPC, i, nRemaining));
        nShown++;
    }

    if (nShown == 0)
    {
        string sNone = (nSel == 0)
            ? "You already know every cantrip."
            : ("You already know every spell of level " + IntToString(nSel)
               + " open to you.");
        jList = JsonArrayInsert(jList, NuiHeight(NuiRow(JsonArrayInsert(
            JsonArray(), NuiWidth(NuiLabel(JsonString(sNone),
                JsonInt(NUI_HALIGN_LEFT), JsonInt(NUI_VALIGN_MIDDLE)),
                CSP_LIST_W - 20.0))), CSP_ROW_H));
    }

    json jGroup = NuiGroup(NuiCol(jList), TRUE, NUI_SCROLLBARS_Y);
    jGroup = NuiWidth(jGroup, CSP_LIST_W);
    jGroup = NuiHeight(jGroup, CSP_LIST_H);
    jCol = JsonArrayInsert(jCol, jGroup);

    string sFoot = "Rest to reopen this window while spells remain to be chosen.";
    jCol = JsonArrayInsert(jCol, NuiHeight(NuiWidth(
        NuiLabel(JsonString(sFoot), JsonInt(NUI_HALIGN_CENTER),
                 JsonInt(NUI_VALIGN_MIDDLE)), CSP_LIST_W), CSP_HDR_H));

    json jFoot = JsonArray();
    jFoot = JsonArrayInsert(jFoot, NuiWidth(
        NuiId(NuiButton(JsonString("Close")), "bclose"), 120.0));
    jCol = JsonArrayInsert(jCol, NuiHeight(NuiRow(jFoot), 32.0));

    return NuiWindow(NuiCol(jCol), JsonString("Spellbook Study"),
        NuiRect(-1.0, -1.0, CSP_WIN_W, CSP_WIN_H),
        JsonBool(FALSE),   // resizable
        JsonBool(FALSE),   // collapsed
        JsonBool(TRUE),    // closable
        JsonBool(FALSE),   // transparent
        JsonBool(TRUE));   // border
}

void CSP_Close(object oPC)
{
    int nTok = GetLocalInt(oPC, CSP_TOK);
    if (nTok) NuiDestroy(oPC, nTok);
    DeleteLocalInt(oPC, CSP_TOK);
}

// Open (or re-open) the picker. Destroys any stale instance first, so calling
// this after a pick is how the list refreshes.
void CSP_Open(object oPC)
{
    if (!GetIsPC(oPC) || GetIsDM(oPC)) return;
    if (CSP_PickerClass(oPC) == CLASS_TYPE_INVALID) return;

    int nOld = NuiFindWindow(oPC, CSP_WIN);
    if (nOld) NuiDestroy(oPC, nOld);

    int nTok = NuiCreate(oPC, CSP_Window(oPC), CSP_WIN, "csp_evt");
    SetLocalInt(oPC, CSP_TOK, nTok);
}
