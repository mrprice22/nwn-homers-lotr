// The Twentieth Plot of Mazarbul (roadmap: twentieth-plot-mazarbul)
// StartingConditional: TRUE for PCs below the level floor who have not yet
// started — Frar will not send green folk against the wraith.
#include "q_maz_inc"

int StartingConditional()
{
    object oPC = GetPCSpeaker();
    return MAZ_GetStage(oPC) == 0 && GetHitDice(oPC) < MAZ_MIN_LVL;
}
