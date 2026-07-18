// The Colour of Power -- Wizard line I (roadmap: wizard-line-early)
// StartingConditional: offer the study -- a Wizard who has not yet begun.
#include "q_wiz_inc"

int StartingConditional()
{
    object oPC = GetPCSpeaker();
    return WIZ_IsWizard(oPC) && WIZ_GetStage(oPC) == 0;
}
