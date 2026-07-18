// Tales That Live Forever -- Bard line I (roadmap: bard-line-early)
// StartingConditional: carrying the Lay and Bard 15+ -- ready for the rapier
// (node 3).
#include "q_bard_inc"

int StartingConditional()
{
    object oPC = GetPCSpeaker();
    return BRD_GetStage(oPC) == 2 && BRD_BardLevel(oPC) >= BRD_LVL_NODE3;
}
