// Blood of Elder Days -- Sorcerer line I (roadmap: sorcerer-line-early)
// StartingConditional: line I complete -- the epilogue greeting.
#include "q_sor_inc"

int StartingConditional()
{
    return SOR_GetStage(GetPCSpeaker()) >= 3;
}
