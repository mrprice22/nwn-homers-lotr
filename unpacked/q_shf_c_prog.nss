// q_shf_c_prog -- TRUE while the trial is under way (stages 1-2):
// Halmir's reminder line. Listed after q_shf_c_rdy on the branch, so it
// only shows when the turn-in line does not (no tuft in hand yet, or
// the tuft was lost -- the pool re-gives it). (roadmap: shifter-quest)
#include "q_shf_inc"

int StartingConditional()
{
    int nStage = QSHF_GetStage(GetPCSpeaker());
    return nStage >= QSHF_STAGE_ACCEPTED && nStage <= QSHF_STAGE_TUFT;
}
