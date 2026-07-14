// Spider Silk Harvest (roadmap: spider-silk-harvest)
// StartingConditional on the turn-in reply: TRUE when the PC carries a full
// day's worth of silk bolts.
#include "q_silk_inc"

int StartingConditional()
{
    return QS_CountBolts(GetPCSpeaker()) >= QS_NEED;
}
