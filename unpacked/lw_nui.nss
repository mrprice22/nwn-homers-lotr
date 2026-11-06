// lw_nui.nss - the Loot Wishlist window (Loot Overhaul Phase 6, lo-wishlist).
//
// Opened from the rest menu ("Loot wishlist...", emotewand.dlg -> lw_open).
// Event handling is in lw_evt.nss, registered per-window via NuiCreate's
// sEventScript. Storage and the PC-side cache are in loot_db.nss; the roll-time
// pick (Loot_WishPick) and the Auto list (Loot_AutoList) are in loot_inc.nss.
//
// SHAPE. One category at a time (the loot/bases.json categories), chosen with
// the row of buttons under the header, then one row per base item with an
// Add / Remove button. A summary pane at the bottom says what is picked and
// what Auto is doing. The window is REBUILT after every change, as csp_nui and
// legfeat_nui are: the header count, the buttons and the summary all move.
//
// The traps this repo's other NUI windows recorded, all respected here:
// resrefs are capped at 16 characters; nw_inc_nui has no `&` reference
// parameters; EVERY child gets an explicit width and the list group an
// explicit size (or it sizes to its longest label and clips the header); and a
// tooltip cannot hold a long string (one line, never wraps, strips "\n"), so
// the long text lives in a `text` widget, which does wrap.

#include "nw_inc_nui"
#include "loot_inc"

const string LW_WIN = "lootwish";     // NuiCreate window id
const string LW_TOK = "LW_TOK";       // PC local: this window's token
const string LW_CAT = "LW_CAT";       // PC local: selected category index, +1

const float LW_WIN_W    = 660.0;
const float LW_WIN_H    = 620.0;
const float LW_LIST_W   = 620.0;
const float LW_LIST_H   = 300.0;
const float LW_COL_BTN  = 90.0;
const float LW_COL_NAME = 220.0;
const float LW_COL_NOTE = 260.0;
const float LW_ROW_H    = 30.0;
const float LW_HDR_H    = 26.0;
const float LW_TAB_W    = 84.0;
const float LW_SUM_H    = 110.0;

void LW_Open(object oPC);
void LW_Close(object oPC);

// Player-facing name of a loot category (LootD_CatName).
string LW_CatLabel(string sCat)
{
    if (sCat == "melee")    return "Melee";
    if (sCat == "ranged")   return "Ranged";
    if (sCat == "armor")    return "Armor";
    if (sCat == "shield")   return "Shields";
    if (sCat == "jewelry")  return "Jewelry";
    if (sCat == "wearable") return "Wearables";
    if (sCat == "caster")   return "Staves";
    return sCat;
}

int LW_Selected(object oPC)
{
    int nSel = GetLocalInt(oPC, LW_CAT) - 1;
    if (nSel < 0 || nSel >= LOOTD_CAT_COUNT) nSel = 0;
    return nSel;
}

// TRUE when nBase is on oPC's Auto list and that list comes from focus feats.
int LW_FeatsFavour(object oPC, int nBase)
{
    string sAuto = Loot_AutoList(oPC);
    if (GetLocalInt(oPC, LOOT_AUTO_TIER) != 1) return FALSE;
    return FindSubString("|" + sAuto, "|" + IntToString(nBase) + ":") >= 0;
}

// "A, B and C" of the base items in a "row:w|row:w|" or "|row|row|" list.
string LW_Names(string sList, int bWeighted)
{
    string sOut = "";
    int nPos = bWeighted ? 0 : 1;
    int nLen = GetStringLength(sList);
    while (nPos < nLen)
    {
        int nEnd = FindSubString(sList, "|", nPos);
        if (nEnd < 0) break;
        string sTok = GetSubString(sList, nPos, nEnd - nPos);
        if (bWeighted) sTok = GetStringLeft(sTok, FindSubString(sTok, ":"));
        int nBase = StringToInt(sTok);
        if (nBase >= 0 && sTok != "")
            sOut += (sOut == "" ? "" : ", ") + LootD_BaseName(nBase);
        nPos = nEnd + 1;
    }
    return sOut;
}

string LW_Summary(object oPC)
{
    string sPct = IntToString(LOOTD_WISH_CHANCE / 10) + "%";
    string sPicks = LW_Names(Loot_WishGet(oPC), FALSE);
    if (sPicks != "")
        return "Your wishlist: " + sPicks + ".\n"
             + sPct + " of the gear rolled for you is one of these, whenever the chest or "
             + "creature can drop that kind of item. (Auto is not used while you have picks.)";
    if (!Loot_WishAutoOn(oPC))
        return "Your wishlist is empty and Auto is off: the loot rolled for you is plain random.";
    string sAuto = Loot_AutoList(oPC);
    int nTier = GetLocalInt(oPC, LOOT_AUTO_TIER);
    if (nTier == 1)
        return "Your wishlist is empty, so Auto is choosing: " + sPct + " of the gear rolled for "
             + "you leans toward the weapons your feats favour - " + LW_Names(sAuto, TRUE) + ".";
    if (nTier == 2)
        return "Your wishlist is empty, so Auto is choosing. You have no weapon focus feats, so "
             + sPct + " of the gear rolled for you leans toward the weapons you are proficient "
             + "with.";
    return "Your wishlist is empty and Auto has nothing to lean toward: the loot rolled for you "
         + "is plain random.";
}

json LW_Row(object oPC, int nBase, int bFull)
{
    int bHas = Loot_WishHas(oPC, nBase);
    json jRow = JsonArray();

    json jBtn = NuiId(NuiButton(JsonString(bHas ? "Remove" : "Add")), "b" + IntToString(nBase));
    jBtn = NuiEnabled(jBtn, JsonBool(bHas || !bFull));
    jRow = JsonArrayInsert(jRow, NuiWidth(jBtn, LW_COL_BTN));

    string sName = LootD_BaseName(nBase);
    if (bHas) sName = "* " + sName;
    jRow = JsonArrayInsert(jRow, NuiWidth(NuiLabel(JsonString(sName),
        JsonInt(NUI_HALIGN_LEFT), JsonInt(NUI_VALIGN_MIDDLE)), LW_COL_NAME));

    string sNote = "";
    if (bHas) sNote = "on your wishlist";
    else if (LW_FeatsFavour(oPC, nBase)) sNote = "your feats favour this";
    jRow = JsonArrayInsert(jRow, NuiWidth(NuiLabel(JsonString(sNote),
        JsonInt(NUI_HALIGN_LEFT), JsonInt(NUI_VALIGN_MIDDLE)), LW_COL_NOTE));

    return NuiHeight(NuiRow(jRow), LW_ROW_H);
}

json LW_Tabs(int nSel)
{
    json jRow = JsonArray();
    int c;
    for (c = 0; c < LOOTD_CAT_COUNT; c++)
    {
        json jBtn = NuiId(NuiButton(JsonString(LW_CatLabel(LootD_CatName(c)))),
                          "c" + IntToString(c));
        jBtn = NuiEnabled(jBtn, JsonBool(c != nSel));
        jRow = JsonArrayInsert(jRow, NuiWidth(jBtn, LW_TAB_W));
    }
    return NuiHeight(NuiRow(jRow), LW_ROW_H);
}

json LW_Label(string s, float fW)
{
    return NuiHeight(NuiWidth(NuiLabel(JsonString(s), JsonInt(NUI_HALIGN_CENTER),
        JsonInt(NUI_VALIGN_MIDDLE)), fW), LW_HDR_H);
}

json LW_Window(object oPC)
{
    int nCount = Loot_WishCount(oPC);
    int bFull = nCount >= LOOTD_WISH_MAX;
    int nSel = LW_Selected(oPC);

    json jCol = JsonArray();
    jCol = JsonArrayInsert(jCol, LW_Label("Wishlist: " + IntToString(nCount) + " of "
        + IntToString(LOOTD_WISH_MAX) + " item types picked", LW_LIST_W));
    jCol = JsonArrayInsert(jCol, LW_Label("Pick the kinds of gear you want random loot to "
        + "favour. Change it any time out of combat.", LW_LIST_W));
    jCol = JsonArrayInsert(jCol, LW_Tabs(nSel));

    json jList = JsonArray();
    int n = LootD_BaseCount(nSel);
    int k;
    for (k = 0; k < n; k++)
        jList = JsonArrayInsert(jList, LW_Row(oPC, LootD_BaseRow(nSel, k), bFull));
    json jGroup = NuiGroup(NuiCol(jList), TRUE, NUI_SCROLLBARS_Y);
    jGroup = NuiWidth(jGroup, LW_LIST_W);
    jGroup = NuiHeight(jGroup, LW_LIST_H);
    jCol = JsonArrayInsert(jCol, jGroup);

    json jSum = NuiText(JsonString(LW_Summary(oPC)), TRUE, NUI_SCROLLBARS_AUTO);
    jSum = NuiWidth(jSum, LW_LIST_W);
    jSum = NuiHeight(jSum, LW_SUM_H);
    jCol = JsonArrayInsert(jCol, jSum);

    int bAuto = Loot_WishAutoOn(oPC);
    json jFoot = JsonArray();
    json jClear = NuiId(NuiButton(JsonString("Clear wishlist")), "bclear");
    jClear = NuiEnabled(jClear, JsonBool(nCount > 0));
    jFoot = JsonArrayInsert(jFoot, NuiWidth(jClear, 150.0));
    json jAuto = NuiId(NuiButton(JsonString(bAuto ? "Auto: on" : "Auto: off")), "bauto");
    jAuto = NuiTooltip(jAuto, JsonString(bAuto ? "Turn Auto off" : "Turn Auto on"));
    jFoot = JsonArrayInsert(jFoot, NuiWidth(jAuto, 150.0));
    jFoot = JsonArrayInsert(jFoot, NuiWidth(NuiId(NuiButton(JsonString("Close")), "bclose"), 120.0));
    jCol = JsonArrayInsert(jCol, NuiHeight(NuiRow(jFoot), 32.0));

    return NuiWindow(NuiCol(jCol), JsonString("Loot Wishlist"),
        NuiRect(-1.0, -1.0, LW_WIN_W, LW_WIN_H),
        JsonBool(FALSE),   // resizable
        JsonBool(FALSE),   // collapsed
        JsonBool(TRUE),    // closable
        JsonBool(FALSE),   // transparent
        JsonBool(TRUE));   // border
}

void LW_Close(object oPC)
{
    int nTok = GetLocalInt(oPC, LW_TOK);
    if (nTok) NuiDestroy(oPC, nTok);
    DeleteLocalInt(oPC, LW_TOK);
}

// Open (or re-open) the window. Destroys any stale instance first, so calling
// this after a change is how it refreshes.
void LW_Open(object oPC)
{
    if (!GetIsPC(oPC) || GetIsDM(oPC)) return;
    int nOld = NuiFindWindow(oPC, LW_WIN);
    if (nOld) NuiDestroy(oPC, nOld);
    SetLocalInt(oPC, LW_TOK, NuiCreate(oPC, LW_Window(oPC), LW_WIN, "lw_evt"));
}
