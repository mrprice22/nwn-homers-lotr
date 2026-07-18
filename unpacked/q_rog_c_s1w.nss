// The Long Shadow -- Rogue line I (roadmap: rogue-line-early)
// StartingConditional: sworn but not yet level 8 -- "come back grown".
#include "q_rog_inc"

int StartingConditional()
{
    object oPC = GetPCSpeaker();
    return ROG_GetStage(oPC) == 1 && GetHitDice(oPC) < ROG_LVL_NODE2;
}
