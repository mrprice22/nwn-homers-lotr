// Oathsworn to the West -- Paladin line I (roadmap: paladin-line-early)
// StartingConditional: sworn but not yet Paladin 8 -- "come back grown".
#include "q_pld_inc"

int StartingConditional()
{
    object oPC = GetPCSpeaker();
    return PLD_GetStage(oPC) == 1 && PLD_PalLevel(oPC) < PLD_LVL_NODE2;
}
