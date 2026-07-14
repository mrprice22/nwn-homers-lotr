// Spider Silk Harvest (roadmap: spider-silk-harvest)
// StartingConditional: TRUE while the harvest is active for the PC (accepted
// today, not yet paid). Sets token 6351 to the number of bolts carried for
// Thranduil's progress line.
#include "q_silk_inc"

int StartingConditional()
{
    object oPC = GetPCSpeaker();
    if (!QS_IsActive(oPC))
        return FALSE;
    SetCustomToken(6351, IntToString(QS_CountBolts(oPC)));
    return TRUE;
}
