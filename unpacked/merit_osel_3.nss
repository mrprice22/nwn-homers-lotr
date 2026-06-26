// merit_osel_3 — Reply action: request the redemption in option slot 3.
#include "merit_redeem"
void main()
{
    object oPC = GetPCSpeaker();
    int nId = GetLocalInt(oPC, "merit_lslot_3");
    if (nId > 0) Merit_RequestById(oPC, nId);
}
