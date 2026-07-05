// dye_nui_inc.nss — "Dye Studio" NUI color picker (all 176 armor-tint colors).
// Launched from the DyeKit item (dye_nui_open) for armor / helmet / cloak.
// Clicking a swatch tints the equipped item live via CopyItemAndModify, preserving
// the forge legality stamps (FORGE_CEIL/FORGE_CLEAN) so dyeing never jails the bearer.
#include "nw_inc_nui"
#include "dye_palette_inc"
#include "dye_db"

// ---- session locals (on the PC) ----
const string DYE_TOK  = "DYE_TOK";    // NUI token
const string DYE_SLOT = "DYE_SLOT";   // INVENTORY_SLOT_* being dyed
const string DYE_CH   = "DYE_CH";     // ITEM_APPR_ARMOR_COLOR_* channel (0..5)
const string DYE_SEL  = "DYE_SEL";    // currently selected color index (highlight)
const string DYE_ITEM = "DYE_ITEM";   // current item object (changes on each apply)
const string DYE_PAGE = "DYE_PAGE";   // current swatch page (0-based)

// The grid is paged: rendering all 176 swatches (each a button + draw list) in
// one window overflows the client's layout builder ("Error constructing window
// from json"). We show one page of DYE_PAGESIZE swatches at a time.
const int DYE_COLS     = 12;
const int DYE_ROWS     = 4;
const int DYE_PAGESIZE = 48;          // DYE_COLS * DYE_ROWS
const int DYE_NPAGES   = 4;           // ceil(176 / 48)

// ---- prototypes ----
int    DyeIsDyeable(object oItem);
int    DyeIsMetal(int nChan);
int    DyeSwatchRGB(int nChan, int nIdx);
string DyeColorName(int nChan, int nIdx);
string DyeChanName(int nChan);
string DyeSlotName(int nSlot);
object DyeGetItem(object oPC);
void   DyeSaveOriginals(object oPC);
json   DyeBuildGridJson(object oPC);
json   DyeBuildControlsJson(object oPC);
json   DyeBuildWindow(object oPC);
object DyeApply(object oPC, int nIdx);
void   DyeUpdateStatus(object oPC);
void   DyeUpdatePageLabel(object oPC);
void   DyeRefresh(object oPC);
void   DyeSetPage(object oPC, int nPage);
void   DyeJumpToSel(object oPC);
void   DyeSelectSlot(object oPC, int nSlot);
void   DyeSelectChannel(object oPC, int nChan);
void   DyeRevert(object oPC);
void   DyeSaveSchemeFromItem(object oPC);
void   DyeApplyScheme(object oPC);
void   DyeCleanup(object oPC);

// ---- helpers ----
int DyeIsDyeable(object oItem) {
    int t = GetBaseItemType(oItem);
    return (t == BASE_ITEM_ARMOR || t == BASE_ITEM_HELMET || t == BASE_ITEM_CLOAK);
}

int DyeIsMetal(int nChan) {
    return (nChan == ITEM_APPR_ARMOR_COLOR_METAL1 || nChan == ITEM_APPR_ARMOR_COLOR_METAL2);
}

// Representative swatch RGB (packed 0xRRGGBB) for a channel+index. Cloth & leather
// share the cloth palette; metal uses the armor(metal) palette.
int DyeSwatchRGB(int nChan, int nIdx) {
    if (DyeIsMetal(nChan)) return DyeMetalRGB(nIdx);
    return DyeClothRGB(nIdx);
}

// Human-readable color name for a channel+index (metal vs cloth palette).
string DyeColorName(int nChan, int nIdx) {
    if (nIdx < 0 || nIdx > 175) return "";
    if (DyeIsMetal(nChan)) return DyeMetalName(nIdx);
    return DyeClothName(nIdx);
}

string DyeChanName(int nChan) {
    switch (nChan) {
        case 2: return "Cloth 1";
        case 3: return "Cloth 2";
        case 0: return "Leather 1";
        case 1: return "Leather 2";
        case 4: return "Metal 1";
        case 5: return "Metal 2";
    }
    return "?";
}

string DyeSlotName(int nSlot) {
    switch (nSlot) {
        case INVENTORY_SLOT_CHEST: return "Armor";
        case INVENTORY_SLOT_HEAD:  return "Helmet";
        case INVENTORY_SLOT_CLOAK: return "Cloak";
    }
    return "?";
}

object DyeGetItem(object oPC) {
    object oItem = GetLocalObject(oPC, DYE_ITEM);
    if (GetIsObjectValid(oItem)) return oItem;
    oItem = GetItemInSlot(GetLocalInt(oPC, DYE_SLOT), oPC);
    if (GetIsObjectValid(oItem)) SetLocalObject(oPC, DYE_ITEM, oItem);
    return oItem;
}

void DyeSaveOneSlot(object oPC, int nSlot) {
    object oItem = GetItemInSlot(nSlot, oPC);
    if (!GetIsObjectValid(oItem) || !DyeIsDyeable(oItem)) return;
    int ch;
    for (ch = 0; ch < 6; ch++)
        SetLocalInt(oPC, "DYE_O_" + IntToString(nSlot) + "_" + IntToString(ch),
                    GetItemAppearance(oItem, ITEM_APPR_TYPE_ARMOR_COLOR, ch));
    SetLocalInt(oPC, "DYE_OS_" + IntToString(nSlot), 1);
}

void DyeSaveOriginals(object oPC) {
    DyeSaveOneSlot(oPC, INVENTORY_SLOT_CHEST);
    DyeSaveOneSlot(oPC, INVENTORY_SLOT_HEAD);
    DyeSaveOneSlot(oPC, INVENTORY_SLOT_CLOAK);
}

// One 30x20 clickable swatch cell (id "sw<idx>"), filled with its palette color,
// with a white border when it is the currently-selected color.
json DyeCell(int nChan, int nIdx, int nSel) {
    int nRGB = DyeSwatchRGB(nChan, nIdx);
    json jFill = NuiColor((nRGB >> 16) & 255, (nRGB >> 8) & 255, nRGB & 255);
    json jList = JsonArray();
    jList = JsonArrayInsert(jList, NuiDrawListRect(JsonBool(TRUE), jFill, JsonBool(TRUE),
                JsonFloat(1.0), NuiRect(0.0, 0.0, 32.0, 24.0),
                NUI_DRAW_LIST_ITEM_ORDER_AFTER, NUI_DRAW_LIST_ITEM_RENDER_ALWAYS, FALSE));
    if (nIdx == nSel)
        jList = JsonArrayInsert(jList, NuiDrawListRect(JsonBool(TRUE), NuiColor(255, 255, 255),
                    JsonBool(FALSE), JsonFloat(2.5), NuiRect(1.0, 1.0, 30.0, 22.0),
                    NUI_DRAW_LIST_ITEM_ORDER_AFTER, NUI_DRAW_LIST_ITEM_RENDER_ALWAYS, FALSE));
    json jCell = NuiButton(JsonString(IntToString(nIdx)));
    jCell = NuiId(jCell, "sw" + IntToString(nIdx));
    jCell = NuiWidth(jCell, 32.0);
    jCell = NuiHeight(jCell, 24.0);
    jCell = NuiDrawList(jCell, JsonBool(FALSE), jList);
    return jCell;
}

// One page of DYE_PAGESIZE swatches (DYE_COLS cols x DYE_ROWS rows), colored for
// the active channel's palette. Empty trailing rows are skipped. Cells have a
// fixed size so the color fill rect lines up; the window must be sized wider than
// DYE_COLS*cell so the NUI layout constraint solver can satisfy the row.
json DyeBuildGridJson(object oPC) {
    int nChan  = GetLocalInt(oPC, DYE_CH);
    int nSel   = GetLocalInt(oPC, DYE_SEL);
    int nStart = GetLocalInt(oPC, DYE_PAGE) * DYE_PAGESIZE;
    json jRows = JsonArray();
    int r, c, idx;
    for (r = 0; r < DYE_ROWS; r++) {
        json jRow = JsonArray();
        int nInRow = 0;
        for (c = 0; c < DYE_COLS; c++) {
            idx = nStart + r * DYE_COLS + c;
            if (idx < 176) { jRow = JsonArrayInsert(jRow, DyeCell(nChan, idx, nSel)); nInRow++; }
        }
        if (nInRow > 0) jRows = JsonArrayInsert(jRows, NuiHeight(NuiRow(jRow), 28.0));
    }
    return NuiCol(jRows);
}

// A fixed-size slot/material button; when selected it gets a highlighted
// background (translucent fill) + bright border via a draw list.
json DyeGridBtn(string sId, string sLabel, int bSelected) {
    json jBtn = NuiButton(JsonString(sLabel));
    jBtn = NuiId(jBtn, sId);
    jBtn = NuiWidth(jBtn, 128.0);
    jBtn = NuiHeight(jBtn, 30.0);
    if (bSelected) {
        json jList = JsonArray();
        jList = JsonArrayInsert(jList, NuiDrawListRect(JsonBool(TRUE), NuiColor(80, 160, 255, 90),
                    JsonBool(TRUE), JsonFloat(1.0), NuiRect(0.0, 0.0, 128.0, 30.0),
                    NUI_DRAW_LIST_ITEM_ORDER_AFTER, NUI_DRAW_LIST_ITEM_RENDER_ALWAYS, FALSE));
        jList = JsonArrayInsert(jList, NuiDrawListRect(JsonBool(TRUE), NuiColor(130, 205, 255),
                    JsonBool(FALSE), JsonFloat(3.0), NuiRect(1.0, 1.0, 126.0, 28.0),
                    NUI_DRAW_LIST_ITEM_ORDER_AFTER, NUI_DRAW_LIST_ITEM_RENDER_ALWAYS, FALSE));
        jBtn = NuiDrawList(jBtn, JsonBool(FALSE), jList);
    }
    return jBtn;
}

// The 3x3 slot/material control grid, with the active slot and active material
// highlighted. Columns = Cloth / Leather / Metal; rows: slots, material 1, material 2.
json DyeBuildControlsJson(object oPC) {
    int nSlot = GetLocalInt(oPC, DYE_SLOT);
    int nChan = GetLocalInt(oPC, DYE_CH);
    json jRows = JsonArray();

    json r0 = JsonArray();
    r0 = JsonArrayInsert(r0, DyeGridBtn("slc", "Armor",  nSlot == INVENTORY_SLOT_CHEST));
    r0 = JsonArrayInsert(r0, DyeGridBtn("slh", "Helmet", nSlot == INVENTORY_SLOT_HEAD));
    r0 = JsonArrayInsert(r0, DyeGridBtn("slk", "Cloak",  nSlot == INVENTORY_SLOT_CLOAK));
    jRows = JsonArrayInsert(jRows, NuiHeight(NuiRow(r0), 32.0));

    json r1 = JsonArray();
    r1 = JsonArrayInsert(r1, DyeGridBtn("ch2", "Cloth 1",   nChan == ITEM_APPR_ARMOR_COLOR_CLOTH1));
    r1 = JsonArrayInsert(r1, DyeGridBtn("ch0", "Leather 1", nChan == ITEM_APPR_ARMOR_COLOR_LEATHER1));
    r1 = JsonArrayInsert(r1, DyeGridBtn("ch4", "Metal 1",   nChan == ITEM_APPR_ARMOR_COLOR_METAL1));
    jRows = JsonArrayInsert(jRows, NuiHeight(NuiRow(r1), 32.0));

    json r2 = JsonArray();
    r2 = JsonArrayInsert(r2, DyeGridBtn("ch3", "Cloth 2",   nChan == ITEM_APPR_ARMOR_COLOR_CLOTH2));
    r2 = JsonArrayInsert(r2, DyeGridBtn("ch1", "Leather 2", nChan == ITEM_APPR_ARMOR_COLOR_LEATHER2));
    r2 = JsonArrayInsert(r2, DyeGridBtn("ch5", "Metal 2",   nChan == ITEM_APPR_ARMOR_COLOR_METAL2));
    jRows = JsonArrayInsert(jRows, NuiHeight(NuiRow(r2), 32.0));

    return NuiCol(jRows);
}

json DyeBuildWindow(object oPC) {
    json jCol = JsonArray();

    // Slot + material controls (group id "ctl" so highlight can be refreshed)
    json jCtl = NuiId(NuiGroup(DyeBuildControlsJson(oPC), FALSE, NUI_SCROLLBARS_NONE), "ctl");
    jCol = JsonArrayInsert(jCol, NuiHeight(jCtl, 104.0));

    // Status label (bound "dstat")
    jCol = JsonArrayInsert(jCol, NuiHeight(NuiLabel(NuiBind("dstat"),
                JsonInt(NUI_HALIGN_CENTER), JsonInt(NUI_VALIGN_MIDDLE)), 20.0));

    // Swatch grid (group id "grid" so it can be refreshed via NuiSetGroupLayout)
    json jGrid = NuiId(NuiGroup(DyeBuildGridJson(oPC), FALSE, NUI_SCROLLBARS_NONE), "grid");
    jCol = JsonArrayInsert(jCol, NuiHeight(jGrid, 130.0));

    // Page navigation row
    json jNav = JsonArray();
    jNav = JsonArrayInsert(jNav, NuiId(NuiButton(JsonString("< Prev colors")), "bprev"));
    jNav = JsonArrayInsert(jNav, NuiLabel(NuiBind("dpage"), JsonInt(NUI_HALIGN_CENTER), JsonInt(NUI_VALIGN_MIDDLE)));
    jNav = JsonArrayInsert(jNav, NuiId(NuiButton(JsonString("More colors >")), "bnext"));
    jCol = JsonArrayInsert(jCol, NuiHeight(NuiRow(jNav), 30.0));

    // Footer row 1
    json jFoot = JsonArray();
    jFoot = JsonArrayInsert(jFoot, NuiId(NuiButton(JsonString("Revert")), "brev"));
    jFoot = JsonArrayInsert(jFoot, NuiId(NuiButton(JsonString("Reshape appearance...")), "bshape"));
    jFoot = JsonArrayInsert(jFoot, NuiId(NuiButton(JsonString("Close")), "bclose"));
    jCol = JsonArrayInsert(jCol, NuiHeight(NuiRow(jFoot), 32.0));

    // Footer row 2 — save/apply a color scheme (persistent per character)
    json jFoot2 = JsonArray();
    jFoot2 = JsonArrayInsert(jFoot2, NuiId(NuiButton(JsonString("Save colors")), "bsave"));
    jFoot2 = JsonArrayInsert(jFoot2, NuiId(NuiButton(JsonString("Apply saved colors")), "bapply"));
    jCol = JsonArrayInsert(jCol, NuiHeight(NuiRow(jFoot2), 32.0));

    // Default the window to the centre of the right half of the screen so it does
    // not cover the character live-preview. Falls back to screen-centre (-1,-1).
    float ww = 520.0;
    float wh = 470.0;
    float wx = -1.0;
    float wy = -1.0;
    int gw = GetPlayerDeviceProperty(oPC, PLAYER_DEVICE_PROPERTY_GUI_WIDTH);
    int gh = GetPlayerDeviceProperty(oPC, PLAYER_DEVICE_PROPERTY_GUI_HEIGHT);
    if (gw > 0 && gh > 0) {
        wx = IntToFloat(gw) * 0.75 - ww / 2.0;
        wy = (IntToFloat(gh) - wh) / 2.0;
        if (wx < 0.0) wx = 0.0;
        if (wy < 0.0) wy = 0.0;
    }

    return NuiWindow(NuiCol(jCol), JsonString("Dye Studio"),
        NuiRect(wx, wy, ww, wh),
        JsonBool(FALSE),   // resizable
        JsonBool(FALSE),   // collapsed
        JsonBool(TRUE),    // closable
        JsonBool(FALSE),   // transparent
        JsonBool(TRUE));   // border
}

// Apply color index nIdx to the current channel of the current slot's item, live.
object DyeApply(object oPC, int nIdx) {
    int nSlot = GetLocalInt(oPC, DYE_SLOT);
    int nChan = GetLocalInt(oPC, DYE_CH);
    object oItem = DyeGetItem(oPC);
    if (!GetIsObjectValid(oItem)) return OBJECT_INVALID;
    int nCeil  = GetLocalInt(oItem, "FORGE_CEIL");
    int nClean = GetLocalInt(oItem, "FORGE_CLEAN");
    object oNew = CopyItemAndModify(oItem, ITEM_APPR_TYPE_ARMOR_COLOR, nChan, nIdx, TRUE);
    if (!GetIsObjectValid(oNew)) return oItem;
    if (nCeil)  SetLocalInt(oNew, "FORGE_CEIL", nCeil);
    if (nClean) SetLocalInt(oNew, "FORGE_CLEAN", nClean);
    DestroyObject(oItem);
    SetLocalObject(oPC, DYE_ITEM, oNew);
    AssignCommand(oPC, ClearAllActions(TRUE));
    AssignCommand(oPC, ActionEquipItem(oNew, nSlot));
    return oNew;
}

void DyeUpdateStatus(object oPC) {
    int nTok = GetLocalInt(oPC, DYE_TOK);
    object oItem = DyeGetItem(oPC);
    int nChan = GetLocalInt(oPC, DYE_CH);
    string s;
    if (!GetIsObjectValid(oItem) || !DyeIsDyeable(oItem))
        s = "No dyeable item equipped.";
    else {
        int nCur = GetItemAppearance(oItem, ITEM_APPR_TYPE_ARMOR_COLOR, nChan);
        // The highlighted slot/material buttons already show which combo is active,
        // so the status line just names the current color.
        s = "Color #" + IntToString(nCur) + "  -  " + DyeColorName(nChan, nCur);
    }
    NuiSetBind(oPC, nTok, "dstat", JsonString(s));
}

void DyeUpdatePageLabel(object oPC) {
    int nPage = GetLocalInt(oPC, DYE_PAGE);
    int nLo = nPage * DYE_PAGESIZE;
    int nHi = nLo + DYE_PAGESIZE - 1;
    if (nHi > 175) nHi = 175;
    NuiSetBind(oPC, GetLocalInt(oPC, DYE_TOK), "dpage",
        JsonString("Colors " + IntToString(nLo) + "-" + IntToString(nHi)
                 + "  (page " + IntToString(nPage + 1) + "/" + IntToString(DYE_NPAGES) + ")"));
}

void DyeRefresh(object oPC) {
    int nTok = GetLocalInt(oPC, DYE_TOK);
    NuiSetGroupLayout(oPC, nTok, "ctl",  DyeBuildControlsJson(oPC));
    NuiSetGroupLayout(oPC, nTok, "grid", DyeBuildGridJson(oPC));
    DyeUpdateStatus(oPC);
    DyeUpdatePageLabel(oPC);
}

// Jump the swatch view to the page holding this combo's current color.
void DyeJumpToSel(object oPC) {
    int nSel = GetLocalInt(oPC, DYE_SEL);
    if (nSel >= 0 && nSel <= 175) SetLocalInt(oPC, DYE_PAGE, nSel / DYE_PAGESIZE);
}

void DyeSetPage(object oPC, int nPage) {
    if (nPage < 0) nPage = 0;
    if (nPage >= DYE_NPAGES) nPage = DYE_NPAGES - 1;
    SetLocalInt(oPC, DYE_PAGE, nPage);
    DyeRefresh(oPC);
}

void DyeSelectSlot(object oPC, int nSlot) {
    SetLocalInt(oPC, DYE_SLOT, nSlot);
    DeleteLocalObject(oPC, DYE_ITEM);
    object oItem = GetItemInSlot(nSlot, oPC);
    if (GetIsObjectValid(oItem)) SetLocalObject(oPC, DYE_ITEM, oItem);
    if (GetIsObjectValid(oItem) && DyeIsDyeable(oItem))
        SetLocalInt(oPC, DYE_SEL, GetItemAppearance(oItem, ITEM_APPR_TYPE_ARMOR_COLOR, GetLocalInt(oPC, DYE_CH)));
    else
        SetLocalInt(oPC, DYE_SEL, -1);
    DyeJumpToSel(oPC);
    DyeRefresh(oPC);
}

void DyeSelectChannel(object oPC, int nChan) {
    SetLocalInt(oPC, DYE_CH, nChan);
    object oItem = DyeGetItem(oPC);
    if (GetIsObjectValid(oItem) && DyeIsDyeable(oItem))
        SetLocalInt(oPC, DYE_SEL, GetItemAppearance(oItem, ITEM_APPR_TYPE_ARMOR_COLOR, nChan));
    else
        SetLocalInt(oPC, DYE_SEL, -1);
    DyeJumpToSel(oPC);
    DyeRefresh(oPC);
}

// Restore the current slot's item to the colors it had when the window opened.
void DyeRevert(object oPC) {
    int nSlot = GetLocalInt(oPC, DYE_SLOT);
    if (!GetLocalInt(oPC, "DYE_OS_" + IntToString(nSlot))) return;
    object oCur = DyeGetItem(oPC);
    if (!GetIsObjectValid(oCur)) return;
    int nCeil  = GetLocalInt(oCur, "FORGE_CEIL");
    int nClean = GetLocalInt(oCur, "FORGE_CLEAN");
    int ch;
    for (ch = 0; ch < 6; ch++) {
        int nVal = GetLocalInt(oPC, "DYE_O_" + IntToString(nSlot) + "_" + IntToString(ch));
        object oTmp = CopyItemAndModify(oCur, ITEM_APPR_TYPE_ARMOR_COLOR, ch, nVal, TRUE);
        if (GetIsObjectValid(oTmp)) { DestroyObject(oCur); oCur = oTmp; }
    }
    if (nCeil)  SetLocalInt(oCur, "FORGE_CEIL", nCeil);
    if (nClean) SetLocalInt(oCur, "FORGE_CLEAN", nClean);
    SetLocalObject(oPC, DYE_ITEM, oCur);
    AssignCommand(oPC, ClearAllActions(TRUE));
    AssignCommand(oPC, ActionEquipItem(oCur, nSlot));
    SetLocalInt(oPC, DYE_SEL, GetLocalInt(oPC, "DYE_O_" + IntToString(nSlot) + "_" + IntToString(GetLocalInt(oPC, DYE_CH))));
    DyeRefresh(oPC);
}

// Save the current item's 6 channel colors as this character's scheme (persistent).
void DyeSaveSchemeFromItem(object oPC) {
    object oItem = DyeGetItem(oPC);
    if (!GetIsObjectValid(oItem) || !DyeIsDyeable(oItem)) {
        SendMessageToPC(oPC, "Dye Studio: no dyeable item to save colors from.");
        return;
    }
    Dye_SaveScheme(oPC,
        GetItemAppearance(oItem, ITEM_APPR_TYPE_ARMOR_COLOR, 0),
        GetItemAppearance(oItem, ITEM_APPR_TYPE_ARMOR_COLOR, 1),
        GetItemAppearance(oItem, ITEM_APPR_TYPE_ARMOR_COLOR, 2),
        GetItemAppearance(oItem, ITEM_APPR_TYPE_ARMOR_COLOR, 3),
        GetItemAppearance(oItem, ITEM_APPR_TYPE_ARMOR_COLOR, 4),
        GetItemAppearance(oItem, ITEM_APPR_TYPE_ARMOR_COLOR, 5));
    NuiSetBind(oPC, GetLocalInt(oPC, DYE_TOK), "dstat",
               JsonString("Saved this item's color scheme."));
}

// Apply this character's saved scheme to the current slot's item (jail-safe).
void DyeApplyScheme(object oPC) {
    if (!Dye_LoadScheme(oPC)) {
        SendMessageToPC(oPC, "Dye Studio: no saved color scheme yet. Use 'Save colors' first.");
        NuiSetBind(oPC, GetLocalInt(oPC, DYE_TOK), "dstat", JsonString("No saved scheme yet."));
        return;
    }
    int nSlot = GetLocalInt(oPC, DYE_SLOT);
    object oCur = DyeGetItem(oPC);
    if (!GetIsObjectValid(oCur) || !DyeIsDyeable(oCur)) {
        SendMessageToPC(oPC, "Dye Studio: no dyeable item to apply colors to.");
        return;
    }
    int nCeil  = GetLocalInt(oCur, "FORGE_CEIL");
    int nClean = GetLocalInt(oCur, "FORGE_CLEAN");
    int ch;
    for (ch = 0; ch < 6; ch++) {
        int nVal = GetLocalInt(oPC, "DYE_LS_" + IntToString(ch));
        object oTmp = CopyItemAndModify(oCur, ITEM_APPR_TYPE_ARMOR_COLOR, ch, nVal, TRUE);
        if (GetIsObjectValid(oTmp)) { DestroyObject(oCur); oCur = oTmp; }
    }
    if (nCeil)  SetLocalInt(oCur, "FORGE_CEIL", nCeil);
    if (nClean) SetLocalInt(oCur, "FORGE_CLEAN", nClean);
    SetLocalObject(oPC, DYE_ITEM, oCur);
    AssignCommand(oPC, ClearAllActions(TRUE));
    AssignCommand(oPC, ActionEquipItem(oCur, nSlot));
    SetLocalInt(oPC, DYE_SEL, GetLocalInt(oPC, "DYE_LS_" + IntToString(GetLocalInt(oPC, DYE_CH))));
    DyeJumpToSel(oPC);
    DyeRefresh(oPC);
}

void DyeCleanup(object oPC) {
    DeleteLocalInt(oPC, DYE_TOK);
    DeleteLocalInt(oPC, DYE_SLOT);
    DeleteLocalInt(oPC, DYE_CH);
    DeleteLocalInt(oPC, DYE_SEL);
    DeleteLocalInt(oPC, DYE_PAGE);
    DeleteLocalObject(oPC, DYE_ITEM);
    DeleteLocalInt(oPC, "DYE_OS_" + IntToString(INVENTORY_SLOT_CHEST));
    DeleteLocalInt(oPC, "DYE_OS_" + IntToString(INVENTORY_SLOT_HEAD));
    DeleteLocalInt(oPC, "DYE_OS_" + IntToString(INVENTORY_SLOT_CLOAK));
}
