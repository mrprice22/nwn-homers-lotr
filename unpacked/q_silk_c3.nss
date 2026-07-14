// Spider Silk Harvest (roadmap: spider-silk-harvest)
// StartingConditional on Thranduil's daily offer entry: level 12+ and neither
// paid nor already hunting today (the done-today and active branches are
// checked first in the dialogue; re-checked here for safety).
#include "q_silk_inc"

int StartingConditional()
{
    object oPC = GetPCSpeaker();
    if (GetHitDice(oPC) < QS_MIN_LVL)
        return FALSE;
    if (QCD_IsDoneToday(oPC, QS_QUEST) || QS_IsActive(oPC))
        return FALSE;
    return TRUE;
}
