#include "zep_inc_craft"

int StartingConditional() {
    object oPC = GetPCSpeaker();
    object oItem = GetItemInSlot(INVENTORY_SLOT_LEFTHAND, oPC);
    if (!GetIsObjectValid(oItem) || GetPlotFlag(oItem) ||
        ZEP_GetIsShield(oItem) || ZEP_GetIsWeapon(oItem))
        return FALSE;

    if (GetIsDM(oPC)) return TRUE;

    object oNPC = GetLocalObject(oPC, "ZEP_CR_NPC");
    if (GetIsObjectValid(oNPC))
        return GetLocalInt(oNPC, "ZEP_CR_MISC") == 1;
    return TRUE;
}
