// Oathsworn to the West -- Paladin line I (roadmap: paladin-line-early)
// StartingConditional: carrying the seal but not yet Paladin 15 -- "return when
// the oath has had its work of you".
#include "q_pld_inc"

int StartingConditional()
{
    object oPC = GetPCSpeaker();
    return PLD_GetStage(oPC) == 2 && PLD_PalLevel(oPC) < PLD_LVL_NODE3;
}
