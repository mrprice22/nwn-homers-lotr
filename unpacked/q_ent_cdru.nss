// The Thirteenth Ent (roadmap: thirteenth-ent)
// StartingConditional: a druid of level 20+ who has not woken Leaflock and
// is not inside the 24-real-hour wait after an attempt.
#include "q_ent_inc"

int StartingConditional()
{
    object oPC = GetPCSpeaker();
    if (ENT_IsRestored(oPC)) return FALSE;
    if (!ENT_IsDruid(oPC)) return FALSE;
    return !QCD_IsOnCooldown(oPC, ENT_CD_DRUID, QCD_DAY);
}
