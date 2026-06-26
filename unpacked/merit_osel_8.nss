// merit_osel_8 — Reply action: request the redemption in option slot 8.
#include "merit_redeem"
void main()
{
    object oPC = GetPCSpeaker();
    int nId = GetLocalInt(oPC, "merit_lslot_8");
    if (nId > 0) Merit_RequestById(oPC, nId);
}
