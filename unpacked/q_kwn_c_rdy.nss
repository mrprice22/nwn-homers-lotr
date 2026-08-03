// q_kwn_c_rdy - Gate Captain: three spears answer, release the standard
// (stage 3). (roadmap: knight-westernesse-quest)
#include "q_kwn_inc"

int StartingConditional()
{
    return QKWN_GetStage(GetPCSpeaker()) == QKWN_STAGE_MUSTERED;
}
