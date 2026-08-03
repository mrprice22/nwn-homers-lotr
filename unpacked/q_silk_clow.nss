// Spider Silk Harvest (roadmap: spider-silk-harvest)
// StartingConditional: TRUE for PCs below the level floor - Thranduil turns
// them away rather than sending them to feed the spiders.
#include "q_silk_inc"

int StartingConditional()
{
    return GetHitDice(GetPCSpeaker()) < QS_MIN_LVL;
}
