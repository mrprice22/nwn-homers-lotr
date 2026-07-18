// The Empty Hand -- Monk line I (roadmap: monk-line-early)
// StartingConditional: taught but not yet Monk 8 -- "come back with less".
#include "q_mnk_inc"

int StartingConditional()
{
    object oPC = GetPCSpeaker();
    return MNK_GetStage(oPC) == 1 && MNK_MonkLevel(oPC) < MNK_LVL_NODE2;
}
