// cbd_page_p - sign: previous page.
#include "cbd_db"
void main()
{
    object oPC = GetPCSpeaker();
    int nOff = GetLocalInt(oPC, "cbd_off") - CBD_PAGE;
    if (nOff < 0) nOff = 0;
    SetLocalInt(oPC, "cbd_off", nOff);
    Cbd_BuildPage(oPC);
}
