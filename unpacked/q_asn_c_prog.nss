// q_asn_c_prog -- TRUE while the trial is under way (stages 1-2):
// Halmir's reminder line. Listed after q_asn_c_rdy on the branch, so it
// only shows when the turn-in line does not (no writ in hand yet, or the
// writ was lost -- the dead drop re-gives it). (roadmap: assassin-quest)
#include "q_asn_inc"

int StartingConditional()
{
    int nStage = QASN_GetStage(GetPCSpeaker());
    return nStage >= QASN_STAGE_ACCEPTED && nStage <= QASN_STAGE_WRIT;
}
