// The Flame of Anor -- Cleric line I (roadmap: cleric-line-early)
// StartingConditional: carrying the reliquary but not yet level 15 -- "return
// when you have kept its flame through the wide world".
#include "q_clr_inc"

int StartingConditional()
{
    object oPC = GetPCSpeaker();
    return CLR_GetStage(oPC) == 2 && GetHitDice(oPC) < CLR_LVL_NODE3;
}
