// brd_page_n - reply action: next page of the fallen.
#include "brd_db"
void main()
{
    object oPC = GetPCSpeaker();
    SetLocalInt(oPC, "brd_page_off", GetLocalInt(oPC, "brd_page_off") + 9);
    BRD_BuildPage(oPC);
}
