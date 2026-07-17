// q_bkg_c_rdy -- TRUE once the PC carries the black brand at stage 2:
// Halmir's turn-in line (GetItemPossessedBy reagent check).
// (roadmap: blackguard-quest)
#include "q_bkg_inc"

int StartingConditional()
{
    object oPC = GetPCSpeaker();
    return QBKG_GetStage(oPC) == QBKG_STAGE_BRAND && QBKG_HasBrand(oPC);
}
