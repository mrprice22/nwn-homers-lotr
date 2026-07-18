// The Colour of Power -- Wizard line I (roadmap: wizard-line-early)
// StartingConditional: line I complete -- the epilogue greeting.
#include "q_wiz_inc"

int StartingConditional()
{
    return WIZ_GetStage(GetPCSpeaker()) >= 3;
}
