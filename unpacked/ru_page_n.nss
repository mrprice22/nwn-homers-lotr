// ru_page_n - reply action: next page of recent updates.
#include "ru_db"
void main()
{
    object oPC = GetPCSpeaker();
    SetLocalInt(oPC, "ru_page_off", GetLocalInt(oPC, "ru_page_off") + 5);
    RU_BuildPage(oPC);
}
