// Tales That Live Forever -- Bard line I (roadmap: bard-line-early)
// StartingConditional: taught and Bard 8+ -- ready for the Lay (node 2).
#include "q_bard_inc"

int StartingConditional()
{
    object oPC = GetPCSpeaker();
    return BRD_GetStage(oPC) == 1 && BRD_BardLevel(oPC) >= BRD_LVL_NODE2;
}
