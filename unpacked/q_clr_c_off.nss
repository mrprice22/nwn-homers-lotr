// The Flame of Anor -- Cleric line I (roadmap: cleric-line-early)
// StartingConditional: offer the calling -- a Cleric who has not yet begun.
#include "q_clr_inc"

int StartingConditional()
{
    object oPC = GetPCSpeaker();
    return CLR_IsCleric(oPC) && CLR_GetStage(oPC) == 0;
}
