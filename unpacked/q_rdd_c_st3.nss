// q_rdd_c_st3 -- TRUE once the PC is counted among the Red Dragon
// Disciples (stage 3+): Halmir's epilogue line.
// (roadmap: red-dragon-disciple-quest)
#include "q_rdd_inc"

int StartingConditional()
{
    return QRDD_GetStage(GetPCSpeaker()) >= QRDD_STAGE_DONE;
}
