// The Breathing of the World -- Druid line I (roadmap: druid-line-early)
// StartingConditional: carrying the seed and level 15+ -- ready to grow the
// staff (node 3).
#include "q_drd_inc"

int StartingConditional()
{
    object oPC = GetPCSpeaker();
    return DRD_GetStage(oPC) == 2 && GetHitDice(oPC) >= DRD_LVL_NODE3;
}
