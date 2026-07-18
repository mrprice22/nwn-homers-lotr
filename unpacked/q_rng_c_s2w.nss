// The Uncrowned Path -- Ranger line I (roadmap: ranger-line-early)
// StartingConditional: carrying the star but not yet level 15 -- "return when
// you have kept the watch through the wide world".
#include "q_rng_inc"

int StartingConditional()
{
    object oPC = GetPCSpeaker();
    return RNG_GetStage(oPC) == 2 && GetHitDice(oPC) < RNG_LVL_NODE3;
}
