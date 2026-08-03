// q_hrp_c_st2 - TRUE while the PC carries the counter-word (stage 2):
// Halmir's turn-in line. (roadmap: harper-scout-quest)
#include "q_hrp_inc"

int StartingConditional()
{
    return QHRP_GetStage(GetPCSpeaker()) == QHRP_STAGE_SOLVED;
}
