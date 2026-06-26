// merit_osel_7 — Reply action: request the redemption in option slot 7.
#include "merit_redeem"
void main()
{
    object oPC = GetPCSpeaker();
    int nId = GetLocalInt(oPC, "merit_lslot_7");
    if (nId > 0) Merit_RequestById(oPC, nId);
}
