// Disenchant confirm: remove the picked permanent property from the target
// item. No gold changes hands - the magic is simply destroyed.
#include "forge_inc"

void main()
{
    object oPC = GetPCSpeaker();
    object oItem = GetLocalObject(oPC, "FORGE_DIS_ITEM");
    int nPick = GetLocalInt(oPC, "FORGE_DIS_PICK");
    if (!GetIsObjectValid(oItem))
        return;
    itemproperty ip = ForgeGetPropByIndexSel(oItem, nPick, FORGE_SEL_REMOVABLE);
    if (GetIsItemPropertyValid(ip))
    {
        ForgeLog("disenchant: PC=" + GetName(oPC) + " item='" + GetName(oItem)
            + "' removing [" + ForgePropName(ip) + "]");
        RemoveItemProperty(oItem, ip);
        // Disenchanting changes the item's legality footprint - drop its "clean"
        // stamp so the next login contraband scan re-evaluates it.
        DeleteLocalInt(oItem, "FORGE_CLEAN");
        // Stripping is a player modification too - stamp it so the
        // caps keep applying to a piece the player has reshaped.
        SetLocalInt(oItem, FORGE_TOUCHED, TRUE);
    }
    // Refresh the list tokens for the re-shown menu.
    ForgeDisenchantSetup(oPC, oItem);
    // Disenchanting may have made the PC lawful - refresh the cached gate
    // verdict off the hot path so the release reply can appear on the next click.
    ForgeBeginWardenScan(oPC);
}
