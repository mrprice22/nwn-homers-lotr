#include "zep_inc_craft"

int StartingConditional() {
    object oPC = GetPCSpeaker();
    object oCloak = GetItemInSlot(INVENTORY_SLOT_CLOAK, oPC);
    if (!GetIsObjectValid(oCloak) || GetPlotFlag(oCloak) || GetBaseItemType(oCloak) != BASE_ITEM_CLOAK)
        return FALSE;

    if (GetIsDM(oPC)) return TRUE;

    object oNPC = GetLocalObject(oPC, "ZEP_CR_NPC");
    if (GetIsObjectValid(oNPC))
        return GetLocalInt(oNPC, "ZEP_CR_CLOAK") == 1;

    return TRUE;
}
