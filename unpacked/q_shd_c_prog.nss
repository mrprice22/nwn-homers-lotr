// q_shd_c_prog -- TRUE while the trial is under way (stages 1-2):
// Halmir's reminder line. Listed after q_shd_c_rdy on the branch, so it
// only shows when the turn-in line does not (no skein in hand yet, or
// the skein was lost -- the well re-gives it). (roadmap: shadowdancer-quest)
#include "q_shd_inc"

int StartingConditional()
{
    int nStage = QSHD_GetStage(GetPCSpeaker());
    return nStage >= QSHD_STAGE_ACCEPTED && nStage <= QSHD_STAGE_SKEIN;
}
