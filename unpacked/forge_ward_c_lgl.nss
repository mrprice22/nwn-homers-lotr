// Forge Warden gate: TRUE when the item under the warden's hammer
// (FORGE_DIS_ITEM) has become lawful - stop offering further removals.
#include "forge_inc"

int StartingConditional()
{
    object oPC = GetPCSpeaker();
    object oItem = GetLocalObject(oPC, "FORGE_DIS_ITEM");
    return ForgePCHolds(oPC, oItem) && !ForgeIsItemIllegal(oItem);
}
