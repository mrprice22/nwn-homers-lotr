// q_pal_c_st3 -- TRUE once the PC is on the pale page (stage 3+):
// Halmir's epilogue line. (roadmap: pale-master-quest)
#include "q_pal_inc"

int StartingConditional()
{
    return QPAL_GetStage(GetPCSpeaker()) >= QPAL_STAGE_DONE;
}
