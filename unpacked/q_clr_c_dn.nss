// The Flame of Anor -- Cleric line I (roadmap: cleric-line-early)
// StartingConditional: line I complete -- the epilogue greeting.
#include "q_clr_inc"

int StartingConditional()
{
    return CLR_GetStage(GetPCSpeaker()) >= 3;
}
