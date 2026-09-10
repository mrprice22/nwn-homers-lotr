// sc_cp_isme -- StartingConditional: is the speaker this account's party crasher?
// Penguin conversation (cp_penguin.dlg). First entry tested, so it wins over the
// "somebody else on your account holds it" and "want to sign up?" greetings.
#include "cp_inc"
int StartingConditional()
{
    return CP_IsCrasher(GetPCSpeaker());
}
