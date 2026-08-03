// q_kwn_c_aft - Gate Captain: the banner flies (stage 5+), epilogue line.
// (roadmap: knight-westernesse-quest)
#include "q_kwn_inc"

int StartingConditional()
{
    return QKWN_GetStage(GetPCSpeaker()) >= QKWN_STAGE_PLANTED;
}
