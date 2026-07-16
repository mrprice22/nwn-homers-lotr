// q_dvc_c_st3 -- TRUE once the PC is counted among the Divine Champions
// (stage 3+): Halmir's epilogue line. (roadmap: divine-champion-quest)
#include "q_dvc_inc"

int StartingConditional()
{
    return QDVC_GetStage(GetPCSpeaker()) >= QDVC_STAGE_DONE;
}
