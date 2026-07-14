// The Riddle Game (roadmap: riddle-game)
// StartingConditional on the "the game is not finished" greeting: TRUE while
// a game session is running for this PC (locals survive within a login; a
// relog clears them and the game simply restarts — the weekly stamp is only
// written at game end).
#include "q_rid_inc"

int StartingConditional()
{
    return GetLocalInt(GetPCSpeaker(), "Q_RID_ACTIVE");
}
