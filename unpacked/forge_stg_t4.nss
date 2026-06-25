// Toggle the plan bit for menu slot 4 on the current page (absolute property
// index = page * FORGE_DIS_SLOTS + 4). The menu re-shows via the D1 entry
// (forge_stg_anvil), which re-primes the per-slot cues.
#include "forge_inc"

void main()
{
    object oPC = GetPCSpeaker();
    ForgeStageToggleBit(oPC,
        GetLocalInt(oPC, "FORGE_STG_PAGE") * FORGE_DIS_SLOTS + 4);
}
