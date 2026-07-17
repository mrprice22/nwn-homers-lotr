// q_bkg_c_prog -- TRUE while the fall is under way (stages 1-2): Halmir's
// reminder line. Listed after q_bkg_c_rdy on the branch, so it only shows
// when the turn-in line does not (no brand in hand yet, or the brand was
// lost -- the rack re-gives it). (roadmap: blackguard-quest)
#include "q_bkg_inc"

int StartingConditional()
{
    int nStage = QBKG_GetStage(GetPCSpeaker());
    return nStage >= QBKG_STAGE_ACCEPTED && nStage <= QBKG_STAGE_BRAND;
}
