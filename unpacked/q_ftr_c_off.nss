// The Unbroken Shield -- Fighter line I (roadmap: fighter-line-early)
// StartingConditional: offer the oath -- Fighter who has not yet begun.
#include "q_ftr_inc"

int StartingConditional()
{
    object oPC = GetPCSpeaker();
    return FTR_IsFighter(oPC) && FTR_GetStage(oPC) == 0;
}
