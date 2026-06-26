// merit_osel_5 — Reply action: request the redemption in option slot 5.
#include "merit_redeem"
void main()
{
    object oPC = GetPCSpeaker();
    int nId = GetLocalInt(oPC, "merit_lslot_5");
    if (nId > 0) Merit_RequestById(oPC, nId);
}
