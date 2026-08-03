// The Twentieth Plot of Mazarbul (roadmap: twentieth-plot-mazarbul)
// StartingConditional: TRUE once the quest is complete (stage 4) - the
// one-off epilogue line; the reward can never be re-earned.
#include "q_maz_inc"

int StartingConditional()
{
    return MAZ_GetStage(GetPCSpeaker()) >= 4;
}
