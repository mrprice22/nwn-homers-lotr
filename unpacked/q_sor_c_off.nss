// Blood of Elder Days -- Sorcerer line I (roadmap: sorcerer-line-early)
// StartingConditional: offer the naming -- a Sorcerer who has not yet begun.
#include "q_sor_inc"

int StartingConditional()
{
    object oPC = GetPCSpeaker();
    return SOR_IsSorc(oPC) && SOR_GetStage(oPC) == 0;
}
