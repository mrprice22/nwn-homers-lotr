// Blood of Elder Days -- Sorcerer line I (roadmap: sorcerer-line-early)
// StartingConditional: named but not yet Sorcerer 8 -- "it has not cost you
// anything yet".
#include "q_sor_inc"

int StartingConditional()
{
    object oPC = GetPCSpeaker();
    return SOR_GetStage(oPC) == 1 && SOR_SorcLevel(oPC) < SOR_LVL_NODE2;
}
