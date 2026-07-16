// q_wpm_c_st3 -- TRUE once the PC is counted among the Weapon Masters
// (stage 3+): Halmir's epilogue line. (roadmap: weapon-master-quest)
#include "q_wpm_inc"

int StartingConditional()
{
    return QWPM_GetStage(GetPCSpeaker()) >= QWPM_STAGE_DONE;
}
