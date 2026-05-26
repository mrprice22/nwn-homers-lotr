#include "zep_inc_craft"

int StartingConditional() {
    object oPC = GetPCSpeaker();
    object oItem = GetItemInSlot(INVENTORY_SLOT_LEFTHAND, oPC);
    if (!GetIsObjectValid(oItem) || GetPlotFlag(oItem) ||
        ZEP_GetIsShield(oItem) || ZEP_GetIsWeapon(oItem)) {
        SetCustomToken(ZEP_CR_TOKENBASE+9, "You do not have a misc held item equipped");
        return TRUE;
    }

    if (GetIsDM(oPC)) return FALSE;

    object oNPC = GetLocalObject(oPC, "ZEP_CR_NPC");
    if (GetIsObjectValid(oNPC)) {
        if (GetLocalInt(oNPC, "ZEP_CR_MISC") == 1) return FALSE;
        SetCustomToken(ZEP_CR_TOKENBASE+9, "This craftsman cannot modify your held item");
        return TRUE;
    }
    return FALSE;
}
