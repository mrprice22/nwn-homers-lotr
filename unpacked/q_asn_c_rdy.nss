// q_asn_c_rdy -- TRUE once the PC carries the writ at stage 2:
// Halmir's turn-in line (GetItemPossessedBy reagent check).
// (roadmap: assassin-quest)
#include "q_asn_inc"

int StartingConditional()
{
    object oPC = GetPCSpeaker();
    return QASN_GetStage(oPC) == QASN_STAGE_WRIT && QASN_HasWrit(oPC);
}
