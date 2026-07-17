// Concerning Hobbits (roadmap: concerning-hobbits)
// StartingConditional on the "now, where were we" greeting: TRUE while a game
// is already running (a mid-game relog or re-talk). Lets the player resume
// the current dispute rather than restarting it.
#include "q_hob_inc"

int StartingConditional()
{
    return GetLocalInt(GetPCSpeaker(), "Q_HOB_ACTIVE");
}
