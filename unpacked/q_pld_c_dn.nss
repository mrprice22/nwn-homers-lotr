// Oathsworn to the West -- Paladin line I (roadmap: paladin-line-early)
// StartingConditional: line I complete -- the epilogue greeting.
#include "q_pld_inc"

int StartingConditional()
{
    return PLD_GetStage(GetPCSpeaker()) >= 3;
}
