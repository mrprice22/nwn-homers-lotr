// Beorn's Garden (roadmap: beorns-garden)
// StartingConditional: TRUE while the garden work is active for the PC
// (accepted today, not yet paid). Sets token 6371 to the pelts carried and
// 6372 to the hives harvested for Grimbeorn's progress line.
#include "q_brn_inc"

int StartingConditional()
{
    object oPC = GetPCSpeaker();
    if (!BRN_IsActive(oPC))
        return FALSE;
    SetCustomToken(6371, IntToString(BRN_CountPelts(oPC)));
    SetCustomToken(6372, IntToString(BRN_CountHoney(oPC)));
    return TRUE;
}
