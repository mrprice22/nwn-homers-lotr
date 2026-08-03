// q_hrp_c_st3 - TRUE once the PC is on the rolls (stage 3+): Halmir's
// epilogue line. (roadmap: harper-scout-quest)
#include "q_hrp_inc"

int StartingConditional()
{
    return QHRP_GetStage(GetPCSpeaker()) >= QHRP_STAGE_DONE;
}
