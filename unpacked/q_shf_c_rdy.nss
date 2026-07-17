// q_shf_c_rdy -- TRUE once the PC carries the tuft at stage 2:
// Halmir's turn-in line (GetItemPossessedBy reagent check).
// (roadmap: shifter-quest)
#include "q_shf_inc"

int StartingConditional()
{
    object oPC = GetPCSpeaker();
    return QSHF_GetStage(oPC) == QSHF_STAGE_TUFT && QSHF_HasTuft(oPC);
}
