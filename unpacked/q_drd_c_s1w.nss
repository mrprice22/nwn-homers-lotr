// The Breathing of the World -- Druid line I (roadmap: druid-line-early)
// StartingConditional: listening but not yet level 8 -- "come back grown".
#include "q_drd_inc"

int StartingConditional()
{
    object oPC = GetPCSpeaker();
    return DRD_GetStage(oPC) == 1 && GetHitDice(oPC) < DRD_LVL_NODE2;
}
