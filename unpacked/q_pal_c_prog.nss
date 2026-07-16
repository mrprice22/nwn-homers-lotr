// q_pal_c_prog -- TRUE while the rite is under way (stages 1-2):
// Halmir's reminder line. Listed after q_pal_c_rdy on the branch, so it
// only shows when the turn-in line does not (no dust in hand yet, or the
// dust was lost -- the tomb re-gives it). (roadmap: pale-master-quest)
#include "q_pal_inc"

int StartingConditional()
{
    int nStage = QPAL_GetStage(GetPCSpeaker());
    return nStage >= QPAL_STAGE_ACCEPTED && nStage <= QPAL_STAGE_DUST;
}
