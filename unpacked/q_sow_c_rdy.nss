// q_sow_c_rdy -- StartingConditional for Ferny's turn-in greeting
// (ferny_convo2): TRUE once all three letters are planted (plant stamp
// newer than the last payout) and none remain in hand.
// (roadmap: sowing-discord-bree)
#include "q_sow_inc"

int StartingConditional()
{
    return QSOW_ReadyToTurnIn(GetPCSpeaker());
}
