// graf_page_p.nss - previous page of whichever level is showing.
#include "graf_inc"
void main()
{
    object oPC = GetPCSpeaker();
    Graf_ClaimOk(oPC);
    int nOff = GetLocalInt(oPC, "graf_page_off") - GRAF_PAGE;
    if (nOff < 0) nOff = 0;
    SetLocalInt(oPC, "graf_page_off", nOff);
    Graf_BuildPage(oPC);
}
