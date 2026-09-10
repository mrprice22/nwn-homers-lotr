// sc_cp_canjoin -- StartingConditional: party is running and this account has
// nobody signed up, so the speaker may claim the slot.
#include "cp_inc"
int StartingConditional()
{
    object oPC = GetPCSpeaker();
    return CP_IsOn() && !CP_HasCrasher(oPC);
}
