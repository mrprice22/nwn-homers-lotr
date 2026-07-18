// The Flame of Anor -- Cleric line I (roadmap: cleric-line-early)
// StartingConditional: tending and level 8+ -- ready for the reliquary (node 2).
#include "q_clr_inc"

int StartingConditional()
{
    object oPC = GetPCSpeaker();
    return CLR_GetStage(oPC) == 1 && GetHitDice(oPC) >= CLR_LVL_NODE2;
}
