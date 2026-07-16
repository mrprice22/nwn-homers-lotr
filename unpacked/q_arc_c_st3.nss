// q_arc_c_st3 -- TRUE once the PC is counted among the Arcane Archers
// (stage 3+): Halmir's epilogue line. (roadmap: arcane-archer-quest)
#include "q_arc_inc"

int StartingConditional()
{
    return QARC_GetStage(GetPCSpeaker()) >= QARC_STAGE_DONE;
}
