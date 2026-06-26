// merit_osel_1 — Reply action: request the redemption in option slot 1.
#include "merit_redeem"
void main()
{
    object oPC = GetPCSpeaker();
    int nId = GetLocalInt(oPC, "merit_lslot_1");
    if (nId > 0) Merit_RequestById(oPC, nId);
}
