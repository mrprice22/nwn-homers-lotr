// q_dvc_c_off -- Halmir's Divine Champions branch: show the vigil offer
// only to a PC who has not started the quest AND whose sword is already
// vowed (1+ Divine Champion level -- the design gate).
// (roadmap: divine-champion-quest)
#include "q_dvc_inc"

int StartingConditional()
{
    object oPC = GetPCSpeaker();
    return QDVC_GetStage(oPC) == QDVC_STAGE_NONE
        && QDVC_IsDivineChampion(oPC);
}
