// tele_set - Overwrite the currently-open save-slot with the PC's current
// position (tele_cur_slot set by the tele_open_N reply that led here).
#include "tele_db"
void main()
{
    object oPC = GetPCSpeaker();
    int nSlot = GetLocalInt(oPC, "tele_cur_slot");
    if (nSlot < 1 || nSlot > 5) return;
    Tele_SaveSlot(oPC, nSlot);
    SetCustomToken(5096, Tele_SlotName(oPC, nSlot));  // refresh sub-menu header
    SendMessageToPC(oPC, "[Teleport] Slot " + IntToString(nSlot)
        + " now points to " + GetName(GetArea(oPC)) + ".");
}
