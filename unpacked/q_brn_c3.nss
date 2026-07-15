// Beorn's Garden (roadmap: beorns-garden)
// StartingConditional on Grimbeorn's daily offer entry: level 12+ and
// neither paid nor already at work today (the done-today and active
// branches are checked first in the dialogue; re-checked here for safety).
#include "q_brn_inc"

int StartingConditional()
{
    object oPC = GetPCSpeaker();
    if (GetHitDice(oPC) < BRN_MIN_LVL)
        return FALSE;
    if (QCD_IsDoneToday(oPC, BRN_QUEST) || BRN_IsActive(oPC))
        return FALSE;
    return TRUE;
}
