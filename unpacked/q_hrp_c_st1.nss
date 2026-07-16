// q_hrp_c_st1 — TRUE while the errand is accepted but the cipher unread
// (stage 1): Halmir's reminder line. (roadmap: harper-scout-quest)
#include "q_hrp_inc"

int StartingConditional()
{
    return QHRP_GetStage(GetPCSpeaker()) == QHRP_STAGE_ACCEPTED;
}
