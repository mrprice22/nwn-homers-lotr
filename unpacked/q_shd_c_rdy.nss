// q_shd_c_rdy -- TRUE once the PC carries the skein at stage 2:
// Halmir's turn-in line (GetItemPossessedBy reagent check).
// (roadmap: shadowdancer-quest)
#include "q_shd_inc"

int StartingConditional()
{
    object oPC = GetPCSpeaker();
    return QSHD_GetStage(oPC) == QSHD_STAGE_SKEIN && QSHD_HasSkein(oPC);
}
