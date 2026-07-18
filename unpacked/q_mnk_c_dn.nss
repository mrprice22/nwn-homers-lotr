// The Empty Hand -- Monk line I (roadmap: monk-line-early)
// StartingConditional: line I complete -- the epilogue greeting.
#include "q_mnk_inc"

int StartingConditional()
{
    return MNK_GetStage(GetPCSpeaker()) >= 3;
}
