// q_kwn_c_mus — Gate Captain: the muster is under way (stage 2).
// (roadmap: knight-westernesse-quest)
#include "q_kwn_inc"

int StartingConditional()
{
    return QKWN_GetStage(GetPCSpeaker()) == QKWN_STAGE_MUSTER;
}
