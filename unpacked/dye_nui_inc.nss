// dye_nui_inc.nss — "Dye Studio" NUI color picker (all 176 armor-tint colors).
// Launched from the DyeKit item (dye_nui_open) for armor / helmet / cloak.
// Clicking a swatch tints the equipped item live via CopyItemAndModify, preserving
// the forge legality stamps (FORGE_CEIL/FORGE_CLEAN) so dyeing never jails the bearer.
#include "nw_inc_nui"
#include "dye_palette_inc"

// ---- session locals (on the PC) ----
const string DYE_TOK  = "DYE_TOK";    // NUI token
const string DYE_SLOT = "DYE_SLOT";   // INVENTORY_SLOT_* being dyed
const string DYE_CH   = "DYE_CH";     // ITEM_APPR_ARMOR_COLOR_* channel (0..5)
const string DYE_SEL  = "DYE_SEL";    // currently selected color index (highlight)
const string DYE_ITEM = "DYE_ITEM";   // current item object (changes on each apply)

// ---- prototypes ----
int    DyeIsDyeable(object oItem);
int    DyeIsMetal(int nChan);
int    DyeSwatchRGB(int nChan, int nIdx);
string DyeChanName(int nChan);
string DyeSlotName(int nSlot);
object DyeGetItem(object oPC);
void   DyeSaveOriginals(object oPC);
json   DyeBuildGridJson(object oPC);
json   DyeBuildWindow(object oPC);
object DyeApply(object oPC, int nIdx);
void   DyeUpdateStatus(object oPC);
void   DyeRefresh(object oPC);
void   DyeSelectSlot(object oPC, int nSlot);
void   DyeSelectChannel(object oPC, int nChan);
void   DyeRevert(object oPC);
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
                JsonFloat(1.0), NuiRect(0.0, 0.0, 30.0, 20.0),
                NUI_DRAW_LIST_ITEM_ORDER_AFTER, NUI_DRAW_LIST_ITEM_RENDER_ALWAYS, FALSE));
    if (nIdx == nSel)
        jList = JsonArrayInsert(jList, NuiDrawListRect(JsonBool(TRUE), NuiColor(255, 255, 255),
                    JsonBool(FALSE), JsonFloat(2.5), NuiRect(1.0, 1.0, 28.0, 18.0),
                    NUI_DRAW_LIST_ITEM_ORDER_AFTER, NUI_DRAW_LIST_ITEM_RENDER_ALWAYS, FALSE));
    json jCell = NuiButton(JsonString(""));
    jCell = NuiId(jCell, "sw" + IntToString(nIdx));
    jCell = NuiWidth(jCell, 30.0);
    jCell = NuiHeight(jCell, 20.0);
    jCell = NuiDrawList(jCell, JsonBool(FALSE), jList);
    return jCell;
}

// 176 cells in 11 rows x 16 cols, colored for the active channel's palette.
json DyeBuildGridJson(object oPC) {
    int nChan = GetLocalInt(oPC, DYE_CH);
    int nSel  = GetLocalInt(oPC, DYE_SEL);
    json jRows = JsonArray();
    int r, c, idx = 0;
    for (r = 0; r < 11; r++) {
        json jRow = JsonArray();
        for (c = 0; c < 16; c++) {
            if (idx < 176) jRow = JsonArrayInsert(jRow, DyeCell(nChan, idx, nSel));
            idx++;
        }
        jRows = JsonArrayInsert(jRows, NuiHeight(NuiRow(jRow), 22.0));
    }
    return NuiCol(jRows);
}

json DyeBuildWindow(object oPC) {
    json jCol = JsonArray();

    // Slot row
    json jSlots = JsonArray();
    jSlots = JsonArrayInsert(jSlots, NuiId(NuiButton(JsonString("Armor")),  "slc"));
    jSlots = JsonArrayInsert(jSlots, NuiId(NuiButton(JsonString("Helmet")), "slh"));
    jSlots = JsonArrayInsert(jSlots, NuiId(NuiButton(JsonString("Cloak")),  "slk"));
    jCol = JsonArrayInsert(jCol, NuiHeight(NuiRow(jSlots), 30.0));

    // Channel row (element id "ch<channelConst>")
    json jCh = JsonArray();
    jCh = JsonArrayInsert(jCh, NuiId(NuiButton(JsonString("Cloth 1")),   "ch2"));
    jCh = JsonArrayInsert(jCh, NuiId(NuiButton(JsonString("Cloth 2")),   "ch3"));
    jCh = JsonArrayInsert(jCh, NuiId(NuiButton(JsonString("Leather 1")), "ch0"));
    jCh = JsonArrayInsert(jCh, NuiId(NuiButton(JsonString("Leather 2")), "ch1"));
    jCh = JsonArrayInsert(jCh, NuiId(NuiButton(JsonString("Metal 1")),   "ch4"));
    jCh = JsonArrayInsert(jCh, NuiId(NuiButton(JsonString("Metal 2")),   "ch5"));
    jCol = JsonArrayInsert(jCol, NuiHeight(NuiRow(jCh), 30.0));

    // Status label (bound "dstat")
    jCol = JsonArrayInsert(jCol, NuiHeight(NuiLabel(NuiBind("dstat"),
                JsonInt(NUI_HALIGN_CENTER), JsonInt(NUI_VALIGN_MIDDLE)), 20.0));

    // Swatch grid (group id "grid" so it can be refreshed via NuiSetGroupLayout)
    json jGrid = NuiId(NuiGroup(DyeBuildGridJson(oPC), FALSE, NUI_SCROLLBARS_NONE), "grid");
    jCol = JsonArrayInsert(jCol, NuiHeight(jGrid, 258.0));

    // Footer
    json jFoot = JsonArray();
    jFoot = JsonArrayInsert(jFoot, NuiId(NuiButton(JsonString("Revert")), "brev"));
    jFoot = JsonArrayInsert(jFoot, NuiId(NuiButton(JsonString("Reshape appearance...")), "bshape"));
    jFoot = JsonArrayInsert(jFoot, NuiId(NuiButton(JsonString("Close")), "bclose"));
    jCol = JsonArrayInsert(jCol, NuiHeight(NuiRow(jFoot), 32.0));

    return NuiWindow(NuiCol(jCol), JsonString("Dye Studio"),
        NuiRect(-1.0, -1.0, 580.0, 440.0),
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
    int nSlot = GetLocalInt(oPC, DYE_SLOT);
    string s;
    if (!GetIsObjectValid(oItem) || !DyeIsDyeable(oItem))
        s = "No dyeable item equipped in the " + DyeSlotName(nSlot) + " slot.";
    else {
        int nCur = GetItemAppearance(oItem, ITEM_APPR_TYPE_ARMOR_COLOR, nChan);
        s = "Slot: " + DyeSlotName(nSlot) + "     Channel: " + DyeChanName(nChan)
          + "     Current color: #" + IntToString(nCur);
    }
    NuiSetBind(oPC, nTok, "dstat", JsonString(s));
}

void DyeRefresh(object oPC) {
    NuiSetGroupLayout(oPC, GetLocalInt(oPC, DYE_TOK), "grid", DyeBuildGridJson(oPC));
    DyeUpdateStatus(oPC);
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
    DyeRefresh(oPC);
}

void DyeSelectChannel(object oPC, int nChan) {
    SetLocalInt(oPC, DYE_CH, nChan);
    object oItem = DyeGetItem(oPC);
    if (GetIsObjectValid(oItem) && DyeIsDyeable(oItem))
        SetLocalInt(oPC, DYE_SEL, GetItemAppearance(oItem, ITEM_APPR_TYPE_ARMOR_COLOR, nChan));
    else
        SetLocalInt(oPC, DYE_SEL, -1);
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

void DyeCleanup(object oPC) {
    DeleteLocalInt(oPC, DYE_TOK);
    DeleteLocalInt(oPC, DYE_SLOT);
    DeleteLocalInt(oPC, DYE_CH);
    DeleteLocalInt(oPC, DYE_SEL);
    DeleteLocalObject(oPC, DYE_ITEM);
    DeleteLocalInt(oPC, "DYE_OS_" + IntToString(INVENTORY_SLOT_CHEST));
    DeleteLocalInt(oPC, "DYE_OS_" + IntToString(INVENTORY_SLOT_HEAD));
    DeleteLocalInt(oPC, "DYE_OS_" + IntToString(INVENTORY_SLOT_CLOAK));
}
