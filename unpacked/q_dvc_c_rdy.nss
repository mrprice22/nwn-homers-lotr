// q_dvc_c_rdy -- TRUE once the PC carries the oath-light at stage 2:
// Halmir's turn-in line (GetItemPossessedBy reagent check).
// (roadmap: divine-champion-quest)
#include "q_dvc_inc"

int StartingConditional()
{
    object oPC = GetPCSpeaker();
    return QDVC_GetStage(oPC) == QDVC_STAGE_LIGHT && QDVC_HasLight(oPC);
}
