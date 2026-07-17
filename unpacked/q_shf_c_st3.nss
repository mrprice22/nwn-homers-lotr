// q_shf_c_st3 -- TRUE once the PC is counted among the Shifters
// (stage 3+): Halmir's epilogue line. (roadmap: shifter-quest)
#include "q_shf_inc"

int StartingConditional()
{
    return QSHF_GetStage(GetPCSpeaker()) >= QSHF_STAGE_DONE;
}
