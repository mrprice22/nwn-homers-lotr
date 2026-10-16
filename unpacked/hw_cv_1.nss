// hw_cv_1 - hw_board.dlg: show the tier-1 prize choices to a PC whose
// unclaimed prize tier this year is 1. hw_board_claim re-checks at grant time.
#include "hw_inc"
int StartingConditional()
{
    object oPC = GetPCSpeaker();
    return HW_ClaimTier(oPC) == 1 && !HW_Claimed(oPC);
}
