// The Long Shadow -- Rogue line I (roadmap: rogue-line-early)
// StartingConditional: sworn and level 8+ -- ready for the token (node 2).
#include "q_rog_inc"

int StartingConditional()
{
    object oPC = GetPCSpeaker();
    return ROG_GetStage(oPC) == 1 && GetHitDice(oPC) >= ROG_LVL_NODE2;
}
