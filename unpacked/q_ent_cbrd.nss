// The Thirteenth Ent (roadmap: thirteenth-ent)
// StartingConditional: a bard of level 20+ who has not woken Leaflock and is
// not inside the 24-real-hour wait after an attempt.
#include "q_ent_inc"

int StartingConditional()
{
    object oPC = GetPCSpeaker();
    if (ENT_IsRestored(oPC)) return FALSE;
    if (!ENT_IsBard(oPC)) return FALSE;
    return !QCD_IsOnCooldown(oPC, ENT_CD_BARD, QCD_DAY);
}
