// Concerning Hobbits (roadmap: concerning-hobbits)
// StartingConditional on the "you win" finale entry: TRUE right after the
// fifth answer when the PC scored QHOB_TO_WIN+ of five (Q_HOB_RESULT set by
// the finalizer in q_hob_inc, cleared on the next game start). Sets token
// 6421 to the final score.
#include "q_hob_inc"

int StartingConditional()
{
    object oPC = GetPCSpeaker();
    if (GetLocalInt(oPC, "Q_HOB_RESULT") != 1)
        return FALSE;
    SetCustomToken(6421, IntToString(GetLocalInt(oPC, "Q_HOB_SCORE")));
    return TRUE;
}
