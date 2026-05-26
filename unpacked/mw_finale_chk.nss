// mw_finale_chk -- dialogue conditional: PC has all 7 guides and hasn't already collected the mixtape.
#include "mw_unlock_inc"
int StartingConditional()
{
    object oPC = GetPCSpeaker();
    if (MW_UnlockCount(oPC) < MW_ROSTER_SIZE) return FALSE;
    if (GetCampaignInt(MW_DB, "finale", oPC)) return FALSE;
    return TRUE;
}
