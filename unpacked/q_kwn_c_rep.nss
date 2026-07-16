// q_kwn_c_rep — Gate Captain: greet the reporting knight (stage 1).
// (roadmap: knight-westernesse-quest)
#include "q_kwn_inc"

int StartingConditional()
{
    return QKWN_GetStage(GetPCSpeaker()) == QKWN_STAGE_ACCEPTED;
}
