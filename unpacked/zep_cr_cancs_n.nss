#include "zep_inc_craft"

int StartingConditional() {
    object oPC = GetPCSpeaker();
    object oShield = GetItemInSlot(INVENTORY_SLOT_LEFTHAND, oPC);
    if (!GetIsObjectValid(oShield) || GetPlotFlag(oShield) || !ZEP_GetIsShield(oShield)) {
        SetCustomToken(ZEP_CR_TOKENBASE+7, "You do not have a shield equipped to modify");
        return TRUE;
    }

    if (GetIsDM(oPC)) return FALSE;

    object oNPC = GetLocalObject(oPC, "ZEP_CR_NPC");
    if (GetIsObjectValid(oNPC)) {
        if (GetLocalInt(oNPC, "ZEP_CR_SHIELD") == 1) return FALSE;
        SetCustomToken(ZEP_CR_TOKENBASE+7, "This craftsman cannot modify your shield");
        return TRUE;
    }
    return FALSE;
}
