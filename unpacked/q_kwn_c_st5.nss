// q_kwn_c_st5 — TRUE once the banner flies over the Pelennor (stage 5):
// Halmir's turn-in line. (roadmap: knight-westernesse-quest)
#include "q_kwn_inc"

int StartingConditional()
{
    return QKWN_GetStage(GetPCSpeaker()) == QKWN_STAGE_PLANTED;
}
