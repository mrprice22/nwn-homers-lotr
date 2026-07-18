// Oathsworn to the West -- Paladin line I (roadmap: paladin-line-early)
// StartingConditional: offer the oath -- a Paladin who has not yet begun.
#include "q_pld_inc"

int StartingConditional()
{
    object oPC = GetPCSpeaker();
    return PLD_IsPaladin(oPC) && PLD_GetStage(oPC) == 0;
}
