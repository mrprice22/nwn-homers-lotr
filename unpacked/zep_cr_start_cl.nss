#include "zep_inc_craft"

void main() {
    object oPC    = GetPCSpeaker();
    object oCloak = GetItemInSlot(INVENTORY_SLOT_CLOAK, oPC);
    if (!GetIsObjectValid(oCloak) || GetBaseItemType(oCloak) != BASE_ITEM_CLOAK) {
        SendMessageToPC(oPC, "[Craft] No cloak equipped.");
        return;
    }
    // ZEP_StartCraft now handles cross-session cleanup internally; calling it
    // when an armor/helmet session is already active is safe. Guard only the
    // same-item case (already crafting this cloak) to avoid re-backing it up.
    object oCurrent = GetLocalObject(oPC, "ZEP_CR_ITEM");
    if (!GetLocalInt(oPC, "ZEP_CR_STARTED") || oCurrent != oCloak)
        ZEP_StartCraft(oPC, oCloak);
    ZEP_SetPart(oPC, ZEP_CR_CLOAK, 0);
}
