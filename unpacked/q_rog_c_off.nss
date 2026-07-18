// The Long Shadow -- Rogue line I (roadmap: rogue-line-early)
// StartingConditional: offer a place in the net -- Rogue who has not yet begun.
#include "q_rog_inc"

int StartingConditional()
{
    object oPC = GetPCSpeaker();
    return ROG_IsRogue(oPC) && ROG_GetStage(oPC) == 0;
}
