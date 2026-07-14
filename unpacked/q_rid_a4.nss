// The Riddle Game (roadmap: riddle-game)
// ActionTaken on displayed answer option 4: record the pick. On the
// seventh answer QRID_Answer finalizes the game (stamp/journal/payout).
#include "q_rid_inc"

void main()
{
    QRID_Answer(GetPCSpeaker(), 4);
}
