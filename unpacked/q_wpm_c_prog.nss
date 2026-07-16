// q_wpm_c_prog -- TRUE while the trial is under way (stages 1-2):
// Halmir's reminder line. Listed after q_wpm_c_rdy on the branch, so it
// only shows when the turn-in line does not (no notch in hand yet, or the
// notch was lost -- the post re-gives it). (roadmap: weapon-master-quest)
#include "q_wpm_inc"

int StartingConditional()
{
    int nStage = QWPM_GetStage(GetPCSpeaker());
    return nStage >= QWPM_STAGE_ACCEPTED && nStage <= QWPM_STAGE_NOTCH;
}
