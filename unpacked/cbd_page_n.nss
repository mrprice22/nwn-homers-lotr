// cbd_page_n - sign: next page.
#include "cbd_db"
void main()
{
    object oPC = GetPCSpeaker();
    SetLocalInt(oPC, "cbd_off", GetLocalInt(oPC, "cbd_off") + CBD_PAGE);
    Cbd_BuildPage(oPC);
}
