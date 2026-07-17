// q_dwd_c_st3 -- TRUE once the PC is counted among the Dwarven
// Defenders (stage 3+): Halmir's epilogue line.
// (roadmap: dwarven-defender-quest)
#include "q_dwd_inc"

int StartingConditional()
{
    return QDWD_GetStage(GetPCSpeaker()) >= QDWD_STAGE_DONE;
}
