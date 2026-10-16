// hw_cv_1 - hw_board.dlg: show the tier-1 prize choices to an unclaimed PC
// whose prize tier this year is 1 or better (1 is best): a winner may pick
// from their own tier or any tier below it, one item in all.
// hw_board_claim re-checks at grant time.
#include "hw_inc"
int StartingConditional()
{
    object oPC = GetPCSpeaker();
    int nTier = HW_ClaimTier(oPC);
    return nTier != 0 && nTier <= 1 && !HW_Claimed(oPC);
}
