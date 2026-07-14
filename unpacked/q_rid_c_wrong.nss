// The Riddle Game (roadmap: riddle-game)
// StartingConditional on the mid-game "wrong answer" entry — the final
// fallback after the win/lose/right branches, so it always fires when
// reached. Sets token 6368 to a rotating gloating taunt.
#include "q_rid_inc"

int StartingConditional()
{
    SetCustomToken(6368, QRID_WrongTaunt(GetLocalInt(GetPCSpeaker(), "Q_RID_IDX")));
    return TRUE;
}
