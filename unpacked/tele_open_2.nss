// tele_open_2 — Reply action: enter save-slot 2's sub-menu. Records the
// active slot for the shared detail entry and refreshes the binding header.
#include "tele_db"
void main()
{
    object oPC = GetPCSpeaker();
    SetLocalInt(oPC, "tele_cur_slot", 2);
    SetCustomToken(5096, Tele_SlotName(oPC, 2));
}
