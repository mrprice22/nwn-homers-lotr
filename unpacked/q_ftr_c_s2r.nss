// The Unbroken Shield -- Fighter line I (roadmap: fighter-line-early)
// StartingConditional: carrying the shard and level 15+ -- ready to reforge (node 3).
#include "q_ftr_inc"

int StartingConditional()
{
    object oPC = GetPCSpeaker();
    return FTR_GetStage(oPC) == 2 && GetHitDice(oPC) >= FTR_LVL_NODE3;
}
