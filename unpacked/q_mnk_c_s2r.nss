// The Empty Hand -- Monk line I (roadmap: monk-line-early)
// StartingConditional: carrying the stone and Monk 15+ -- ready for the kama
// (node 3).
#include "q_mnk_inc"

int StartingConditional()
{
    object oPC = GetPCSpeaker();
    return MNK_GetStage(oPC) == 2 && MNK_MonkLevel(oPC) >= MNK_LVL_NODE3;
}
