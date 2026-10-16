// hw_cv_3 - hw_board.dlg: show the tier-3 prize choices to a PC whose
// unclaimed prize tier this year is 3. hw_board_claim re-checks at grant time.
#include "hw_inc"
int StartingConditional()
{
    object oPC = GetPCSpeaker();
    return HW_ClaimTier(oPC) == 3 && !HW_Claimed(oPC);
}
