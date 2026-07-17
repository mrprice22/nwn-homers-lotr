// q_bkg_c_st3 -- TRUE once the PC is counted among the Blackguards (stage
// 3+): Halmir's epilogue line. (roadmap: blackguard-quest)
#include "q_bkg_inc"

int StartingConditional()
{
    return QBKG_GetStage(GetPCSpeaker()) >= QBKG_STAGE_DONE;
}
