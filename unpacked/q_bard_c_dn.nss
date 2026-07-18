// Tales That Live Forever -- Bard line I (roadmap: bard-line-early)
// StartingConditional: line I complete -- the epilogue greeting.
#include "q_bard_inc"

int StartingConditional()
{
    return BRD_GetStage(GetPCSpeaker()) >= 3;
}
