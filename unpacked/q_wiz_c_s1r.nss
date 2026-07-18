// The Colour of Power -- Wizard line I (roadmap: wizard-line-early)
// StartingConditional: studying and level 8+ -- ready for the tome (node 2).
#include "q_wiz_inc"

int StartingConditional()
{
    object oPC = GetPCSpeaker();
    return WIZ_GetStage(oPC) == 1 && GetHitDice(oPC) >= WIZ_LVL_NODE2;
}
