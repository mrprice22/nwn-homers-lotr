// q_hrp_c_g1 - Della's cipher greeting: only for a PC on the errand
// (stage 1). Everyone else gets the plain-traveller line.
// (roadmap: harper-scout-quest)
#include "q_hrp_inc"

int StartingConditional()
{
    return QHRP_GetStage(GetPCSpeaker()) == QHRP_STAGE_ACCEPTED;
}
