// q_pal_c_rdy -- TRUE once the PC carries the grave-dust at stage 2:
// Halmir's turn-in line. The GetItemPossessedBy reagent check from the
// design card. (roadmap: pale-master-quest)
#include "q_pal_inc"

int StartingConditional()
{
    object oPC = GetPCSpeaker();
    return QPAL_GetStage(oPC) == QPAL_STAGE_DUST && QPAL_HasDust(oPC);
}
