// The Uncrowned Path -- Ranger line I (roadmap: ranger-line-early)
// StartingConditional: offer the vigil -- a Ranger who has not yet begun.
#include "q_rng_inc"

int StartingConditional()
{
    object oPC = GetPCSpeaker();
    return RNG_IsRanger(oPC) && RNG_GetStage(oPC) == 0;
}
