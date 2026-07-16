// q_rdd_c_prog -- TRUE while the trial is under way (stages 1-2):
// Halmir's reminder line. Listed after q_rdd_c_rdy on the branch, so it
// only shows when the turn-in line does not (no ember in hand yet, or
// the ember was lost -- the forge re-gives it).
// (roadmap: red-dragon-disciple-quest)
#include "q_rdd_inc"

int StartingConditional()
{
    int nStage = QRDD_GetStage(GetPCSpeaker());
    return nStage >= QRDD_STAGE_ACCEPTED && nStage <= QRDD_STAGE_EMBER;
}
