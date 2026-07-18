// Blood of Elder Days -- Sorcerer line I (roadmap: sorcerer-line-early)
// StartingConditional: carrying the shard and Sorcerer 15+ -- ready for the
// staff (node 3).
#include "q_sor_inc"

int StartingConditional()
{
    object oPC = GetPCSpeaker();
    return SOR_GetStage(oPC) == 2 && SOR_SorcLevel(oPC) >= SOR_LVL_NODE3;
}
