// legfeat_nui.nss — the Legendary Feats picker window.
//
// Opened at character level 60 (legfeat_lvl, from NWNX_ON_LEVEL_UP_AFTER) and
// re-openable from the rest menu while picks remain. Event handling is in
// legfeat_evt.nss, registered per-window via NuiCreate's sEventScript.
//
// WHY A CUSTOM PICKER. The engine's own level-up feat page hands out exactly one
// general feat at 60 to everybody, so the 1 / 2 / 3 allotment cannot be
// expressed to it — and legendary feats are deliberately invisible to it
// (ALLCLASSESCANUSE = 0 in feat.2da). This window is the only grant path.
//
// The window is REBUILT rather than updated after each pick: a taken feat turns
// from a button into a plain line, and the remaining-picks header changes. That
// is cheaper to get right than binding every row's enabled-state, and the list
// is short.
//
// Two traps already recorded against this repo's other NUI windows apply here:
// resrefs are capped at 16 characters, and nw_inc_nui has no `&` reference
// parameters. Both are respected below.

#include "nw_inc_nui"
#include "legfeat_inc"

const string LEGFEAT_WIN = "legfeats";     // NuiCreate window id
const string LEGFEAT_TOK = "LEGFEAT_TOK";  // PC local: this window's token

json LegFeat_Window(object oPC);
void LegFeat_Open(object oPC);
void LegFeat_Close(object oPC);

// One list entry: either a "Take" button (id "t<index>") or, once taken, a
// plain line saying so.
json LegFeat_Row(object oPC, int nIndex, int nRemaining)
{
    int nFeatId = LegFeat_IdAt(nIndex);
    int bTaken  = LegFeat_HasPick(oPC, nFeatId);

    json jRow = JsonArray();
    if (bTaken)
    {
        jRow = JsonArrayInsert(jRow, NuiWidth(
            NuiLabel(JsonString("[taken]"), JsonInt(NUI_HALIGN_CENTER),
                     JsonInt(NUI_VALIGN_MIDDLE)), 70.0));
    }
    else
    {
        json jBtn = NuiId(NuiButton(JsonString("Take")), "t" + IntToString(nIndex));
        // Greyed out rather than hidden when no picks are left, so the player can
        // still read the whole pool and decide before spending.
        jBtn = NuiEnabled(jBtn, JsonBool(nRemaining > 0));
        jBtn = NuiTooltip(jBtn, JsonString(LegFeat_DescAt(nIndex)));
        jRow = JsonArrayInsert(jRow, NuiWidth(jBtn, 70.0));
    }

    json jName = NuiLabel(JsonString(LegFeat_NameAt(nIndex)),
                          JsonInt(NUI_HALIGN_LEFT), JsonInt(NUI_VALIGN_MIDDLE));
    jRow = JsonArrayInsert(jRow, NuiWidth(jName, 170.0));

    json jDesc = NuiLabel(JsonString(LegFeat_DescAt(nIndex)),
                          JsonInt(NUI_HALIGN_LEFT), JsonInt(NUI_VALIGN_MIDDLE));
    jDesc = NuiTooltip(jDesc, JsonString(LegFeat_DescAt(nIndex)));
    jRow = JsonArrayInsert(jRow, jDesc);

    return NuiHeight(NuiRow(jRow), 28.0);
}

json LegFeat_Window(object oPC)
{
    int nRemaining = LegFeat_Remaining(oPC);
    json jCol = JsonArray();

    string sHdr;
    if (nRemaining > 0)
        sHdr = "You may choose " + IntToString(nRemaining) + " legendary feat"
             + ((nRemaining == 1) ? "." : "s.");
    else
        sHdr = "You have spent all of your legendary feats.";
    jCol = JsonArrayInsert(jCol, NuiHeight(
        NuiLabel(JsonString(sHdr), JsonInt(NUI_HALIGN_CENTER),
                 JsonInt(NUI_VALIGN_MIDDLE)), 24.0));
    jCol = JsonArrayInsert(jCol, NuiHeight(
        NuiLabel(JsonString("Choices are permanent."),
                 JsonInt(NUI_HALIGN_CENTER), JsonInt(NUI_VALIGN_MIDDLE)), 20.0));

    // The list is scrollable so later content categories can grow it without a
    // layout rewrite.
    json jList = JsonArray();
    int i;
    for (i = 0; i < LEGFEAT_COUNT; i++)
        jList = JsonArrayInsert(jList, LegFeat_Row(oPC, i, nRemaining));
    jCol = JsonArrayInsert(jCol, NuiGroup(NuiCol(jList), FALSE, NUI_SCROLLBARS_AUTO));

    json jFoot = JsonArray();
    jFoot = JsonArrayInsert(jFoot, NuiId(NuiButton(JsonString("Close")), "bclose"));
    jCol = JsonArrayInsert(jCol, NuiHeight(NuiRow(jFoot), 32.0));

    return NuiWindow(NuiCol(jCol), JsonString("Legendary Feats"),
        NuiRect(-1.0, -1.0, 620.0, 400.0),
        JsonBool(FALSE),   // resizable
        JsonBool(FALSE),   // collapsed
        JsonBool(TRUE),    // closable
        JsonBool(FALSE),   // transparent
        JsonBool(TRUE));   // border
}

void LegFeat_Close(object oPC)
{
    int nTok = GetLocalInt(oPC, LEGFEAT_TOK);
    if (nTok) NuiDestroy(oPC, nTok);
    DeleteLocalInt(oPC, LEGFEAT_TOK);
}

// Open (or re-open) the picker. Destroys any stale instance first, so calling
// this after a pick is how the list refreshes.
void LegFeat_Open(object oPC)
{
    if (!GetIsPC(oPC) || GetIsDM(oPC)) return;

    int nOld = NuiFindWindow(oPC, LEGFEAT_WIN);
    if (nOld) NuiDestroy(oPC, nOld);

    int nTok = NuiCreate(oPC, LegFeat_Window(oPC), LEGFEAT_WIN, "legfeat_evt");
    SetLocalInt(oPC, LEGFEAT_TOK, nTok);
}
