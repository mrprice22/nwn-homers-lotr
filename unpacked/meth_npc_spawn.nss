// meth_npc_spawn — OnSpawn for the two Methonash's Place NPCs (methonashmart,
// methonashforge). Runs the default spawn behaviour (which also records the
// creature's "spawn" location for leash_to_area), then bakes a permanent EVIL
// visual glow onto whatever weapon(s) the NPC is holding. The NPCs' equipped
// gear has had all real item properties stripped in area042.git.json, so this
// is purely cosmetic — they look menacing but their kamas carry no powers.
//
// Reuses the proven pattern from inc_emotewand::AddItemPropertyVisualEffect
// (the Bree weaponfx NPC): IPRemoveMatchingItemProperties + IPSafeAddItemProperty.

#include "x2_inc_itemprop"

void GlowEvil(int nSlot)
{
    object oItem = GetItemInSlot(nSlot, OBJECT_SELF);
    if (!GetIsObjectValid(oItem)) return;
    IPRemoveMatchingItemProperties(oItem, ITEM_PROPERTY_VISUALEFFECT,
                                   DURATION_TYPE_PERMANENT, -1);
    IPSafeAddItemProperty(oItem, ItemPropertyVisualEffect(ITEM_VISUAL_EVIL));
}

void main()
{
    // Default AI spawn + leash home recording.
    ExecuteScript("x2_def_spawn", OBJECT_SELF);

    GlowEvil(INVENTORY_SLOT_RIGHTHAND);
    GlowEvil(INVENTORY_SLOT_LEFTHAND);
}
