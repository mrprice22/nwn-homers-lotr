// The Long Shadow -- Rogue line I (roadmap: rogue-line-early)
// StartingConditional: carrying the token and level 15+ -- ready to reforge (node 3).
#include "q_rog_inc"

int StartingConditional()
{
    object oPC = GetPCSpeaker();
    return ROG_GetStage(oPC) == 2 && GetHitDice(oPC) >= ROG_LVL_NODE3;
}
