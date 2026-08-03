// ru_page_p - reply action: previous page of recent updates.
#include "ru_db"
void main()
{
    object oPC = GetPCSpeaker();
    int nOff = GetLocalInt(oPC, "ru_page_off") - 5;
    if (nOff < 0) nOff = 0;
    SetLocalInt(oPC, "ru_page_off", nOff);
    RU_BuildPage(oPC);
}
