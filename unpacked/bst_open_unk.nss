// bst_open_unk - reply action: open the "Not Yet Slain" list (page 1).
#include "bst_db"
void main()
{
    object oPC = GetPCSpeaker();
    SetLocalInt(oPC, "bst_mode", 1);
    SetLocalInt(oPC, "bst_page_off", 0);
    Bst_BuildPage(oPC);
}
