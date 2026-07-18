// The Uncrowned Path -- Ranger line I (roadmap: ranger-line-early)
// StartingConditional: watching and level 8+ -- ready for the star (node 2).
#include "q_rng_inc"

int StartingConditional()
{
    object oPC = GetPCSpeaker();
    return RNG_GetStage(oPC) == 1 && GetHitDice(oPC) >= RNG_LVL_NODE2;
}
