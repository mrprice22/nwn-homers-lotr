// q_rdd_c_rdy -- TRUE once the PC carries the ember at stage 2:
// Halmir's turn-in line (GetItemPossessedBy reagent check).
// (roadmap: red-dragon-disciple-quest)
#include "q_rdd_inc"

int StartingConditional()
{
    object oPC = GetPCSpeaker();
    return QRDD_GetStage(oPC) == QRDD_STAGE_EMBER && QRDD_HasEmber(oPC);
}
