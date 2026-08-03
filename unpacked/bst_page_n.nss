// bst_page_n - reply action: next page of the current bestiary section.
#include "bst_db"
void main()
{
    object oPC = GetPCSpeaker();
    SetLocalInt(oPC, "bst_page_off", GetLocalInt(oPC, "bst_page_off") + 9);
    Bst_BuildPage(oPC);
}
