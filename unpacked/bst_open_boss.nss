// bst_open_boss - reply action: open the "Bosses Not Yet Slain" list (page 1).
// Mode 2 lists the Roll of the Fallen registry bosses this character has still
// to fell - the set that unlocks the great forges' extra property slot.
#include "bst_db"
void main()
{
    object oPC = GetPCSpeaker();
    SetLocalInt(oPC, "bst_mode", 2);
    SetLocalInt(oPC, "bst_page_off", 0);
    Bst_BuildPage(oPC);
}
