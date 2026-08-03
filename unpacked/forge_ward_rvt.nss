// Forge Warden: revert the item under the hammer (FORGE_DIS_ITEM) to its
// stock blueprint. Sets FORGE_RVT_OK so the dialog can branch on success.
#include "forge_inc"

void main()
{
    object oPC = GetPCSpeaker();
    object oItem = GetLocalObject(oPC, "FORGE_DIS_ITEM");
    // Stale/recycled handle guard: never revert something this PC no longer
    // holds - re-resolve to their current illegal item instead.
    if (!ForgePCHolds(oPC, oItem))
    {
        oItem = ForgeFindIllegalItem(oPC);
        if (!GetIsObjectValid(oItem))
        {
            SetLocalInt(oPC, "FORGE_RVT_OK", FALSE);
            return;
        }
        SetLocalObject(oPC, "FORGE_ILLEGAL_ITEM", oItem);
        SetLocalObject(oPC, "FORGE_DIS_ITEM", oItem);
    }
    object oNew = ForgeRevertToBlueprint(oItem, oPC);
    if (GetIsObjectValid(oNew))
    {
        SetLocalInt(oPC, "FORGE_RVT_OK", TRUE);
        SetLocalObject(oPC, "FORGE_ILLEGAL_ITEM", oNew);
        ForgeDisenchantSetup(oPC, oNew);
        SetCustomToken(6119, ForgeLegalStatus(oNew));
    }
    else
        SetLocalInt(oPC, "FORGE_RVT_OK", FALSE);
    // Reverting an item changes the contraband picture - refresh the cached gate
    // verdict off the hot path so the release reply tracks the new state.
    ForgeBeginWardenScan(oPC);
}
