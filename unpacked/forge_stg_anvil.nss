// Staged anvil disenchant menu entry: prime the property list, per-slot cues
// (tokens 6110-6117) and the running status header (token 6119) for the item on
// the anvil. Starts each visit with an empty plan so a re-opened menu is fresh.
#include "forge_inc"

void main()
{
    object oPC = GetPCSpeaker();
    object oItem = GetLocalObject(oPC, "MODIFY_ITEM");
    // Fresh plan + first page whenever the menu opens on a different item.
    if (oItem != GetLocalObject(oPC, "FORGE_STG_ITEM"))
    {
        ForgeStageClear(oPC);
        DeleteLocalInt(oPC, "FORGE_STG_PAGE");
    }
    ForgeStageSetupCued(oPC, oItem);
}
