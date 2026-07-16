// q_wpm_c_rdy -- TRUE once the PC carries the notch at stage 2:
// Halmir's turn-in line (GetItemPossessedBy reagent check).
// (roadmap: weapon-master-quest)
#include "q_wpm_inc"

int StartingConditional()
{
    object oPC = GetPCSpeaker();
    return QWPM_GetStage(oPC) == QWPM_STAGE_NOTCH && QWPM_HasNotch(oPC);
}
