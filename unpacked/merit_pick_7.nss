// merit_pick_7 - Reply action: prepare the confirmation step for option slot 7.
#include "merit_redeem"
void main()
{
    object oPC = GetPCSpeaker();
    Merit_PrepConfirm(oPC, GetLocalInt(oPC, "merit_lslot_7"));
}
