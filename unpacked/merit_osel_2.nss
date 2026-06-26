// merit_osel_2 — Reply action: request the redemption in option slot 2.
#include "merit_redeem"
void main()
{
    object oPC = GetPCSpeaker();
    int nId = GetLocalInt(oPC, "merit_lslot_2");
    if (nId > 0) Merit_RequestById(oPC, nId);
}
