// q_dvc_c_prog -- TRUE while the vigil is under way (stages 1-2):
// Halmir's reminder line. Listed after q_dvc_c_rdy on the branch, so it
// only shows when the turn-in line does not (no oath-light in hand yet,
// or the light was lost -- the altar re-gives it).
// (roadmap: divine-champion-quest)
#include "q_dvc_inc"

int StartingConditional()
{
    int nStage = QDVC_GetStage(GetPCSpeaker());
    return nStage >= QDVC_STAGE_ACCEPTED && nStage <= QDVC_STAGE_LIGHT;
}
