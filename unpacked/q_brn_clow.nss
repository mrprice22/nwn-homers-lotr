// Beorn's Garden (roadmap: beorns-garden)
// StartingConditional: TRUE for PCs below the level floor - Grimbeorn sends
// them home rather than feeding them to the wargs.
#include "q_brn_inc"

int StartingConditional()
{
    return GetHitDice(GetPCSpeaker()) < BRN_MIN_LVL;
}
