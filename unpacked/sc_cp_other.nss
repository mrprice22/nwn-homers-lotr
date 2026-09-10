// sc_cp_other -- StartingConditional: the speaker's ACCOUNT has already signed a
// character up, and it is not this one.
//
// Also primes custom token 6600 with that character's name, because "another of
// your characters" is a maddening thing to be told when you cannot remember
// which. Setting it here is the right moment: StartingConditionals run before
// the entry's text is rendered, whereas a script ON the entry would not (the
// same ordering trap ammorep_open.nss documents).
//
// Token 6600 is a fresh block: 6100-6102 (colours), 6500-6518 (graffiti) and
// 90001-2 (prize wheel) are taken, and 50xx is already double-booked.
#include "cp_inc"
int StartingConditional()
{
    object oPC = GetPCSpeaker();
    if (CP_IsCrasher(oPC)) return FALSE;
    if (!CP_HasCrasher(oPC)) return FALSE;

    string sWho = CP_CrasherName(oPC);
    SetCustomToken(6600, sWho == "" ? "another of your characters" : sWho);
    return TRUE;
}
