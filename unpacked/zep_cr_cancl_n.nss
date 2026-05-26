#include "zep_inc_craft"

int StartingConditional() {
    object oPC = GetPCSpeaker();
    object oCloak = GetItemInSlot(INVENTORY_SLOT_CLOAK, oPC);
    if (!GetIsObjectValid(oCloak) || GetPlotFlag(oCloak) || GetBaseItemType(oCloak) != BASE_ITEM_CLOAK) {
        SetCustomToken(ZEP_CR_TOKENBASE+8, "You do not have a cloak equipped to modify");
        return TRUE;
    }

    if (GetIsDM(oPC)) return FALSE;

    object oNPC = GetLocalObject(oPC, "ZEP_CR_NPC");
    if (GetIsObjectValid(oNPC)) {
        if (GetLocalInt(oNPC, "ZEP_CR_CLOAK") == 1) return FALSE;
        SetCustomToken(ZEP_CR_TOKENBASE+8, "This craftsman cannot modify your cloak");
        return TRUE;
    }
    return FALSE;
}
