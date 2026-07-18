// The Uncrowned Path -- Ranger line I (roadmap: ranger-line-early)
// StartingConditional: watching but not yet level 8 -- "come back grown".
#include "q_rng_inc"

int StartingConditional()
{
    object oPC = GetPCSpeaker();
    return RNG_GetStage(oPC) == 1 && GetHitDice(oPC) < RNG_LVL_NODE2;
}
