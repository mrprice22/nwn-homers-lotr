// The Riddle Game (roadmap: riddle-game)
// StartingConditional on the "it loses" finale entry: TRUE right after the
// seventh answer when the PC scored fewer than 5 of 7. Sets token 6361 to
// the final score for the wretch's gloating.
#include "q_rid_inc"

int StartingConditional()
{
    object oPC = GetPCSpeaker();
    if (GetLocalInt(oPC, "Q_RID_RESULT") != 2)
        return FALSE;
    SetCustomToken(6361, IntToString(GetLocalInt(oPC, "Q_RID_SCORE")));
    return TRUE;
}
