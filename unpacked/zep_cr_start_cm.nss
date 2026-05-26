#include "zep_inc_craft"

void main() {
    object oPC = GetPCSpeaker();
    object oItem = GetItemInSlot(INVENTORY_SLOT_LEFTHAND, oPC);
    object oCurrent = GetLocalObject(oPC, "ZEP_CR_ITEM");
    if (!GetLocalInt(oPC, "ZEP_CR_STARTED") || oCurrent != oItem)
        ZEP_StartCraft(oPC, oItem);
    ZEP_SetPart(oPC, ZEP_CR_MISC, 0);
}
