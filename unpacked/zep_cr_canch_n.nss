#include "zep_inc_craft"

int StartingConditional() {
    object oPC = GetPCSpeaker();
    object oHelmet = GetItemInSlot(INVENTORY_SLOT_HEAD, oPC);
    if (!GetIsObjectValid(oHelmet) || GetPlotFlag(oHelmet)) {
        SetCustomToken(ZEP_CR_TOKENBASE+6, "You do not have a helmet equipped to modify");
        return TRUE;
    }

    if (GetIsDM(oPC)) return FALSE;

    object oNPC = GetLocalObject(oPC, "ZEP_CR_NPC");
    if (GetIsObjectValid(oNPC)) {
        if (GetLocalInt(oNPC, "ZEP_CR_HELMET") == 1) return FALSE;
        SetCustomToken(ZEP_CR_TOKENBASE+6, "This craftsman cannot modify your helmet");
        return TRUE;
    }
    return FALSE;
}
