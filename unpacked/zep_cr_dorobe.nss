#include "zep_inc_craft"

void main() {
    object oPC = GetPCSpeaker();
    // Only start a new session if one isn't already active. When the player
    // arrives here via the armor sub-menu (zep_cr_start_ca), the session is
    // already running for the chest armor — calling ZEP_StartCraft again
    // would orphan the existing backup in the work container and create a
    // spurious TEMPITEM that gets quarantined on the next area entry check.
    if (!GetLocalInt(oPC, "ZEP_CR_STARTED")) {
        object oArmor = GetItemInSlot(INVENTORY_SLOT_CHEST, oPC);
        ZEP_StartCraft(oPC, oArmor);
    }
    ZEP_SetPart(oPC, ITEM_APPR_ARMOR_MODEL_ROBE, 107993);
}
