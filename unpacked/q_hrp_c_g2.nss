// q_hrp_c_g2 - Della's reminder greeting: the PC already carries the
// counter-word (stage 2). (roadmap: harper-scout-quest)
#include "q_hrp_inc"

int StartingConditional()
{
    return QHRP_GetStage(GetPCSpeaker()) == QHRP_STAGE_SOLVED;
}
