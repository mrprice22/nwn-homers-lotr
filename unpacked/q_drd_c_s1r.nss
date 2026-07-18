// The Breathing of the World -- Druid line I (roadmap: druid-line-early)
// StartingConditional: listening and level 8+ -- ready for the seed (node 2).
#include "q_drd_inc"

int StartingConditional()
{
    object oPC = GetPCSpeaker();
    return DRD_GetStage(oPC) == 1 && GetHitDice(oPC) >= DRD_LVL_NODE2;
}
