// Blood of Elder Days -- Sorcerer line I (roadmap: sorcerer-line-early)
// StartingConditional: named and Sorcerer 8+ -- ready for the shard (node 2).
#include "q_sor_inc"

int StartingConditional()
{
    object oPC = GetPCSpeaker();
    return SOR_GetStage(oPC) == 1 && SOR_SorcLevel(oPC) >= SOR_LVL_NODE2;
}
