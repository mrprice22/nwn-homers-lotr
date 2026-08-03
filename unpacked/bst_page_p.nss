// bst_page_p - reply action: previous page of the current bestiary section.
#include "bst_db"
void main()
{
    object oPC = GetPCSpeaker();
    int nOff = GetLocalInt(oPC, "bst_page_off") - 9;
    if (nOff < 0) nOff = 0;
    SetLocalInt(oPC, "bst_page_off", nOff);
    Bst_BuildPage(oPC);
}
