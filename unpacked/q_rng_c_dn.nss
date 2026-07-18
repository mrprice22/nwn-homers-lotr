// The Uncrowned Path -- Ranger line I (roadmap: ranger-line-early)
// StartingConditional: line I complete -- the epilogue greeting.
#include "q_rng_inc"

int StartingConditional()
{
    return RNG_GetStage(GetPCSpeaker()) >= 3;
}
