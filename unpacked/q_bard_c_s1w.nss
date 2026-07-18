// Tales That Live Forever -- Bard line I (roadmap: bard-line-early)
// StartingConditional: taught but not yet Bard 8 -- "go and let the world
// happen to you".
#include "q_bard_inc"

int StartingConditional()
{
    object oPC = GetPCSpeaker();
    return BRD_GetStage(oPC) == 1 && BRD_BardLevel(oPC) < BRD_LVL_NODE2;
}
