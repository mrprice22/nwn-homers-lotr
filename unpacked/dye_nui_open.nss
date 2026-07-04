// dye_nui_open.nss — opens the Dye Studio NUI. ExecuteScript target from the
// DyeKit item activation (dmfi_activate). OBJECT_SELF is the activating PC.
#include "dye_nui_inc"

void main() {
    object oPC = OBJECT_SELF;
    if (!GetIsPC(oPC)) return;

    // Close any stale instance.
    int nOld = NuiFindWindow(oPC, "dyestudio");
    if (nOld) { NuiDestroy(oPC, nOld); DyeCleanup(oPC); }

    // Default slot: first equipped dyeable of armor / cloak / helmet.
    int nSlot = -1;
    if (DyeIsDyeable(GetItemInSlot(INVENTORY_SLOT_CHEST, oPC)))      nSlot = INVENTORY_SLOT_CHEST;
    else if (DyeIsDyeable(GetItemInSlot(INVENTORY_SLOT_CLOAK, oPC))) nSlot = INVENTORY_SLOT_CLOAK;
    else if (DyeIsDyeable(GetItemInSlot(INVENTORY_SLOT_HEAD, oPC)))  nSlot = INVENTORY_SLOT_HEAD;
    if (nSlot == -1) {
        SendMessageToPC(oPC, "Dye Studio: equip armor, a helmet, or a cloak first.");
        return;
    }

    DyeSaveOriginals(oPC);
    SetLocalInt(oPC, DYE_SLOT, nSlot);
    SetLocalInt(oPC, DYE_CH, ITEM_APPR_ARMOR_COLOR_CLOTH1);
    DeleteLocalObject(oPC, DYE_ITEM);
    object oItem = GetItemInSlot(nSlot, oPC);
    SetLocalObject(oPC, DYE_ITEM, oItem);
    SetLocalInt(oPC, DYE_SEL, GetItemAppearance(oItem, ITEM_APPR_TYPE_ARMOR_COLOR, ITEM_APPR_ARMOR_COLOR_CLOTH1));

    int nTok = NuiCreate(oPC, DyeBuildWindow(oPC), "dyestudio", "dye_nui_evt");
    SetLocalInt(oPC, DYE_TOK, nTok);
    DyeUpdateStatus(oPC);
}
