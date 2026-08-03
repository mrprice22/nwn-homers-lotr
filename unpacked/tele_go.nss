// tele_go - Teleport to the currently-open save-slot (tele_cur_slot set by the
// tele_open_N reply that led into this sub-menu).
#include "tele_db"
void main()
{
    object oPC = GetPCSpeaker();
    int nSlot = GetLocalInt(oPC, "tele_cur_slot");
    if (nSlot < 1 || nSlot > 5 || !Tele_HasSlot(oPC, nSlot))
    {
        SendMessageToPC(oPC, "[Teleport] That slot is empty.");
        return;
    }
    Tele_DoJump(oPC, Tele_SlotLocation(oPC, nSlot), VFX_FNF_PWKILL, VFX_IMP_UNSUMMON);
}
