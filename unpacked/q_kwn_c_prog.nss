// q_kwn_c_prog - TRUE while the proving is under way (stages 1-4):
// Halmir's reminder line. (roadmap: knight-westernesse-quest)
#include "q_kwn_inc"

int StartingConditional()
{
    int nStage = QKWN_GetStage(GetPCSpeaker());
    return nStage >= QKWN_STAGE_ACCEPTED && nStage <= QKWN_STAGE_STANDARD;
}
