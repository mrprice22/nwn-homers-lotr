// q_shd_c_st3 -- TRUE once the PC is counted among the Shadowdancers
// (stage 3+): Halmir's epilogue line. (roadmap: shadowdancer-quest)
#include "q_shd_inc"

int StartingConditional()
{
    return QSHD_GetStage(GetPCSpeaker()) >= QSHD_STAGE_DONE;
}
