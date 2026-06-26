// merit_osel_4 — Reply action: request the redemption in option slot 4.
#include "merit_redeem"
void main()
{
    object oPC = GetPCSpeaker();
    int nId = GetLocalInt(oPC, "merit_lslot_4");
    if (nId > 0) Merit_RequestById(oPC, nId);
}
