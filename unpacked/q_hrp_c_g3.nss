// q_hrp_c_g3 - Della's greeting for a made Harper (stage 3+).
// (roadmap: harper-scout-quest)
#include "q_hrp_inc"

int StartingConditional()
{
    return QHRP_GetStage(GetPCSpeaker()) >= QHRP_STAGE_DONE;
}
