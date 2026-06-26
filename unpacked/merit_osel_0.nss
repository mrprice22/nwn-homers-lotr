// merit_osel_0 — Reply action: request the redemption in option slot 0.
#include "merit_redeem"
void main()
{
    object oPC = GetPCSpeaker();
    int nId = GetLocalInt(oPC, "merit_lslot_0");
    if (nId > 0) Merit_RequestById(oPC, nId);
}
