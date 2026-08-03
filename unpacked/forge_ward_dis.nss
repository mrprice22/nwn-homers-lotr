// Forge Warden disenchant menu entry script: target the confiscation-flagged
// item (set by forge_ward_intro) rather than an anvil item.
#include "forge_inc"

void main()
{
    object oPC = GetPCSpeaker();
    object oItem = GetLocalObject(oPC, "FORGE_ILLEGAL_ITEM");
    // Stale/recycled handle guard: the cached item must still be on this PC
    // (it may be legal already - mid-disenchant entries show its status).
    if (!ForgePCHolds(oPC, oItem))
    {
        oItem = ForgeFindIllegalItem(oPC);
        SetLocalObject(oPC, "FORGE_ILLEGAL_ITEM", oItem);
    }
    ForgeDisenchantSetup(oPC, oItem);
    SetCustomToken(6119, ForgeLegalStatus(oItem));
}
