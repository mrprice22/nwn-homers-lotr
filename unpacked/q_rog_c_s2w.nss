// The Long Shadow -- Rogue line I (roadmap: rogue-line-early)
// StartingConditional: carrying the token but not yet level 15 -- "return when
// you have walked the long roads".
#include "q_rog_inc"

int StartingConditional()
{
    object oPC = GetPCSpeaker();
    return ROG_GetStage(oPC) == 2 && GetHitDice(oPC) < ROG_LVL_NODE3;
}
