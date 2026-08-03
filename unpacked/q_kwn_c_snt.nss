// q_kwn_c_snt - Gate Captain: the standard is out, pointer to the
// banner-stone (stage 4). (roadmap: knight-westernesse-quest)
#include "q_kwn_inc"

int StartingConditional()
{
    return QKWN_GetStage(GetPCSpeaker()) == QKWN_STAGE_STANDARD;
}
