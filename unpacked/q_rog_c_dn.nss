// The Long Shadow -- Rogue line I (roadmap: rogue-line-early)
// StartingConditional: line I complete -- the epilogue greeting.
#include "q_rog_inc"

int StartingConditional()
{
    return ROG_GetStage(GetPCSpeaker()) >= 3;
}
