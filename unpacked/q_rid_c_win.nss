// The Riddle Game (roadmap: riddle-game)
// StartingConditional on the "it wins" finale entry: TRUE right after the
// seventh answer when the PC scored 5+ of 7 (Q_RID_RESULT is set by the
// finalizer in q_rid_inc and cleared on the next game start). Sets token
// 6361 to the final score for the wretch's grumbling.
#include "q_rid_inc"

int StartingConditional()
{
    object oPC = GetPCSpeaker();
    if (GetLocalInt(oPC, "Q_RID_RESULT") != 1)
        return FALSE;
    SetCustomToken(6361, IntToString(GetLocalInt(oPC, "Q_RID_SCORE")));
    return TRUE;
}
