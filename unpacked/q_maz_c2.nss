// The Twentieth Plot of Mazarbul (roadmap: twentieth-plot-mazarbul)
// StartingConditional: TRUE while the wraith must be destroyed (stage 2).
#include "q_maz_inc"

int StartingConditional()
{
    return MAZ_GetStage(GetPCSpeaker()) == 2;
}
