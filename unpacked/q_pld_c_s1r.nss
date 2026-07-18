// Oathsworn to the West -- Paladin line I (roadmap: paladin-line-early)
// StartingConditional: sworn and Paladin 8+ -- ready for the sealed oath (node 2).
#include "q_pld_inc"

int StartingConditional()
{
    object oPC = GetPCSpeaker();
    return PLD_GetStage(oPC) == 1 && PLD_PalLevel(oPC) >= PLD_LVL_NODE2;
}
