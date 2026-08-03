// tele_open_3 - Reply action: enter save-slot 3's sub-menu. Records the
// active slot for the shared detail entry and refreshes the binding header.
#include "tele_db"
void main()
{
    object oPC = GetPCSpeaker();
    SetLocalInt(oPC, "tele_cur_slot", 3);
    SetCustomToken(5096, Tele_SlotName(oPC, 3));
}
