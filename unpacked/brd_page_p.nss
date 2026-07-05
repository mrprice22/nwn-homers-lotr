// brd_page_p — reply action: previous page of the fallen.
#include "brd_db"
void main()
{
    object oPC = GetPCSpeaker();
    int nOff = GetLocalInt(oPC, "brd_page_off") - 9;
    if (nOff < 0) nOff = 0;
    SetLocalInt(oPC, "brd_page_off", nOff);
    BRD_BuildPage(oPC);
}
