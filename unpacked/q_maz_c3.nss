// The Twentieth Plot of Mazarbul (roadmap: twentieth-plot-mazarbul)
// StartingConditional: TRUE when the wraith is slain and the turn-in is due
// (stage 3).
#include "q_maz_inc"

int StartingConditional()
{
    return MAZ_GetStage(GetPCSpeaker()) == 3;
}
