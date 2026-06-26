// merit_osel_6 — Reply action: request the redemption in option slot 6.
#include "merit_redeem"
void main()
{
    object oPC = GetPCSpeaker();
    int nId = GetLocalInt(oPC, "merit_lslot_6");
    if (nId > 0) Merit_RequestById(oPC, nId);
}
