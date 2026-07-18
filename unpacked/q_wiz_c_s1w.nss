// The Colour of Power -- Wizard line I (roadmap: wizard-line-early)
// StartingConditional: studying but not yet level 8 -- "come back grown".
#include "q_wiz_inc"

int StartingConditional()
{
    object oPC = GetPCSpeaker();
    return WIZ_GetStage(oPC) == 1 && GetHitDice(oPC) < WIZ_LVL_NODE2;
}
