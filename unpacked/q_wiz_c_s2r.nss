// The Colour of Power -- Wizard line I (roadmap: wizard-line-early)
// StartingConditional: carrying the tome and level 15+ -- ready to bind the
// staff (node 3).
#include "q_wiz_inc"

int StartingConditional()
{
    object oPC = GetPCSpeaker();
    return WIZ_GetStage(oPC) == 2 && GetHitDice(oPC) >= WIZ_LVL_NODE3;
}
