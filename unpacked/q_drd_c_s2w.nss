// The Breathing of the World -- Druid line I (roadmap: druid-line-early)
// StartingConditional: carrying the seed but not yet level 15 -- "return when
// the wood has had its work of you".
#include "q_drd_inc"

int StartingConditional()
{
    object oPC = GetPCSpeaker();
    return DRD_GetStage(oPC) == 2 && GetHitDice(oPC) < DRD_LVL_NODE3;
}
