// Commit the staged disenchant: strike every planned property from the real
// item and stamp it lawful. Only reachable from a reply gated by forge_stg_ok,
// so the result is always within the law - the item never becomes illegal.
#include "forge_inc"

void main()
{
    object oPC = GetPCSpeaker();
    ForgeStageCommit(oPC, GetLocalObject(oPC, "FORGE_STG_ITEM"));
}
