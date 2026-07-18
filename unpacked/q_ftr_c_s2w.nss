// The Unbroken Shield -- Fighter line I (roadmap: fighter-line-early)
// StartingConditional: carrying the shard but not yet level 15 -- "return when
// you have grown to a captain's years".
#include "q_ftr_inc"

int StartingConditional()
{
    object oPC = GetPCSpeaker();
    return FTR_GetStage(oPC) == 2 && GetHitDice(oPC) < FTR_LVL_NODE3;
}
