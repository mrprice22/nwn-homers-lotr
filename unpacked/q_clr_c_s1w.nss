// The Flame of Anor -- Cleric line I (roadmap: cleric-line-early)
// StartingConditional: tending but not yet level 8 -- "come back grown".
#include "q_clr_inc"

int StartingConditional()
{
    object oPC = GetPCSpeaker();
    return CLR_GetStage(oPC) == 1 && GetHitDice(oPC) < CLR_LVL_NODE2;
}
