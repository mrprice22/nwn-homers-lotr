// The Uncrowned Path -- Ranger line I (roadmap: ranger-line-early)
// StartingConditional: carrying the star and level 15+ -- ready to work the bow
// (node 3).
#include "q_rng_inc"

int StartingConditional()
{
    object oPC = GetPCSpeaker();
    return RNG_GetStage(oPC) == 2 && GetHitDice(oPC) >= RNG_LVL_NODE3;
}
