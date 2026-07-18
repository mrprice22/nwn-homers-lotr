// The Colour of Power -- Wizard line I (roadmap: wizard-line-early)
// StartingConditional: carrying the tome but not yet level 15 -- "return when
// you have studied the wide world".
#include "q_wiz_inc"

int StartingConditional()
{
    object oPC = GetPCSpeaker();
    return WIZ_GetStage(oPC) == 2 && GetHitDice(oPC) < WIZ_LVL_NODE3;
}
