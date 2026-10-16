// hw_cv_2 - hw_board.dlg: show the tier-2 prize choices to a PC whose
// unclaimed prize tier this year is 2. hw_board_claim re-checks at grant time.
#include "hw_inc"
int StartingConditional()
{
    object oPC = GetPCSpeaker();
    return HW_ClaimTier(oPC) == 2 && !HW_Claimed(oPC);
}
