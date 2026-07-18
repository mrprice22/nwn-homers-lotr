// The Breathing of the World -- Druid line I (roadmap: druid-line-early)
// StartingConditional: offer the listening -- a Druid who has not yet begun.
#include "q_drd_inc"

int StartingConditional()
{
    object oPC = GetPCSpeaker();
    return DRD_IsDruid(oPC) && DRD_GetStage(oPC) == 0;
}
