// Tales That Live Forever -- Bard line I (roadmap: bard-line-early)
// StartingConditional: offer the lesson -- a Bard who has not yet begun.
#include "q_bard_inc"

int StartingConditional()
{
    object oPC = GetPCSpeaker();
    return BRD_IsBard(oPC) && BRD_GetStage(oPC) == 0;
}
