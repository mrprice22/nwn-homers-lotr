// Tales That Live Forever -- Bard line I (roadmap: bard-line-early)
// StartingConditional: carrying the Lay but not yet Bard 15 -- the ending has
// not come and found you.
#include "q_bard_inc"

int StartingConditional()
{
    object oPC = GetPCSpeaker();
    return BRD_GetStage(oPC) == 2 && BRD_BardLevel(oPC) < BRD_LVL_NODE3;
}
