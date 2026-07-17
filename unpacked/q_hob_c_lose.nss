// Concerning Hobbits (roadmap: concerning-hobbits)
// StartingConditional on the "you lose" finale entry: TRUE right after the
// fifth answer when the PC scored fewer than QHOB_TO_WIN of five. Sets token
// 6421 to the final score.
#include "q_hob_inc"

int StartingConditional()
{
    object oPC = GetPCSpeaker();
    if (GetLocalInt(oPC, "Q_HOB_RESULT") != 2)
        return FALSE;
    SetCustomToken(6421, IntToString(GetLocalInt(oPC, "Q_HOB_SCORE")));
    return TRUE;
}
