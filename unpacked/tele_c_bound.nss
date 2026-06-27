// tele_c_bound — Conditional: show "Teleport to <slot>" only when the currently
// open save-slot has a saved location.
#include "tele_db"
int StartingConditional()
{
    object oPC = GetPCSpeaker();
    return Tele_HasSlot(oPC, GetLocalInt(oPC, "tele_cur_slot"));
}
