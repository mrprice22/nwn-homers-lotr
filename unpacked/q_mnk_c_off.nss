// The Empty Hand -- Monk line I (roadmap: monk-line-early)
// StartingConditional: offer the lesson -- a Monk who has not yet begun.
#include "q_mnk_inc"

int StartingConditional()
{
    object oPC = GetPCSpeaker();
    return MNK_IsMonk(oPC) && MNK_GetStage(oPC) == 0;
}
