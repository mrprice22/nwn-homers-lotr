// Anvil-forge conversation cleanup — wired to the dialog's EndConversation AND
// EndConverAbort hooks (mirrors forge_ward_clr for the Forge Warden). Without it
// the cached item handle (MODIFY_ITEM) and the staged-disenchant plan/page linger
// on the PC between conversations: the smith would speak about a stale item and a
// half-finished strip plan could leave the status token (6119) showing
// "<UNRECOGNIZED TOKEN>" on the next greeting. Every fresh conversation now starts
// from a clean slate and re-derives the live anvil item.
#include "forge_inc"

void main()
{
    object oPC = GetPCSpeaker();
    if (GetIsObjectValid(oPC))
    {
        DeleteLocalObject(oPC, "MODIFY_ITEM");
        DeleteLocalObject(oPC, "MODIFY_COPY");
        DeleteLocalInt(oPC, "MODIFY_VALUE");
        DeleteLocalInt(oPC, "MODIFY_DIFF");
        DeleteLocalInt(oPC, "MODIFY_MAX");
        DeleteLocalInt(oPC, "MODIFY_MAX_PROPS");
        DeleteLocalObject(oPC, "FORGE_STG_ITEM");
        DeleteLocalInt(oPC, "FORGE_STG_PAGE");
        DeleteLocalInt(oPC, "FORGE_DIS_COUNT");
        DeleteLocalInt(oPC, "FORGE_DIS_PICK");
        ForgeStageClear(oPC);
    }
    // Preserve the smith's stock walk-back-to-post behaviour.
    ExecuteScript("nw_walk_wp", OBJECT_SELF);
}
