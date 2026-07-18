// The Flame of Anor -- Cleric line I (roadmap: cleric-line-early)
// StartingConditional: carrying the reliquary and level 15+ -- ready to kindle
// the mace (node 3).
#include "q_clr_inc"

int StartingConditional()
{
    object oPC = GetPCSpeaker();
    return CLR_GetStage(oPC) == 2 && GetHitDice(oPC) >= CLR_LVL_NODE3;
}
