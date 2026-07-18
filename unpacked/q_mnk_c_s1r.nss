// The Empty Hand -- Monk line I (roadmap: monk-line-early)
// StartingConditional: taught and Monk 8+ -- ready for the stone (node 2).
#include "q_mnk_inc"

int StartingConditional()
{
    object oPC = GetPCSpeaker();
    return MNK_GetStage(oPC) == 1 && MNK_MonkLevel(oPC) >= MNK_LVL_NODE2;
}
