// Blood of Elder Days -- Sorcerer line I (roadmap: sorcerer-line-early)
// StartingConditional: carrying the shard but not yet Sorcerer 15 -- the
// reckoning has not come round yet.
#include "q_sor_inc"

int StartingConditional()
{
    object oPC = GetPCSpeaker();
    return SOR_GetStage(oPC) == 2 && SOR_SorcLevel(oPC) < SOR_LVL_NODE3;
}
