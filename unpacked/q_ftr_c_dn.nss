// The Unbroken Shield -- Fighter line I (roadmap: fighter-line-early)
// StartingConditional: line I complete -- the epilogue greeting.
#include "q_ftr_inc"

int StartingConditional()
{
    return FTR_GetStage(GetPCSpeaker()) >= 3;
}
