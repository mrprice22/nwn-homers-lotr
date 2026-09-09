// mw_finale_chk -- dialogue conditional: PC has all 7 guides and hasn't already collected the mixtape.
#include "mw_unlock_inc"
int StartingConditional()
{
    object oPC = GetPCSpeaker();
    MW_MigrateLegacy(oPC);
    if (MW_UnlockCount(oPC) < MW_ROSTER_SIZE) return FALSE;
    if (MW_GetFlag(oPC, "finale")) return FALSE;
    return TRUE;
}
