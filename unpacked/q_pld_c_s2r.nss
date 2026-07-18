// Oathsworn to the West -- Paladin line I (roadmap: paladin-line-early)
// StartingConditional: carrying the seal and Paladin 15+ -- ready for the sword
// (node 3).
#include "q_pld_inc"

int StartingConditional()
{
    object oPC = GetPCSpeaker();
    return PLD_GetStage(oPC) == 2 && PLD_PalLevel(oPC) >= PLD_LVL_NODE3;
}
