// q_kwn_c_st6 - TRUE once the PC is on the rolls (stage 6+): Halmir's
// epilogue line. (roadmap: knight-westernesse-quest)
#include "q_kwn_inc"

int StartingConditional()
{
    return QKWN_GetStage(GetPCSpeaker()) >= QKWN_STAGE_DONE;
}
