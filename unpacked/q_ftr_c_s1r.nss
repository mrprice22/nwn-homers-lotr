// The Unbroken Shield -- Fighter line I (roadmap: fighter-line-early)
// StartingConditional: oath taken and level 8+ -- ready for the shard (node 2).
#include "q_ftr_inc"

int StartingConditional()
{
    object oPC = GetPCSpeaker();
    return FTR_GetStage(oPC) == 1 && GetHitDice(oPC) >= FTR_LVL_NODE2;
}
