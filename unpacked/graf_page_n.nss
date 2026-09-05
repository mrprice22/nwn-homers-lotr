// graf_page_n.nss - next page of whichever level is showing.
#include "graf_inc"
void main()
{
    object oPC = GetPCSpeaker();
    Graf_ClaimOk(oPC);
    SetLocalInt(oPC, "graf_page_off", GetLocalInt(oPC, "graf_page_off") + GRAF_PAGE);
    Graf_BuildPage(oPC);
}
