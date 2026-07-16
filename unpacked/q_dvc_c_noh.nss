// q_dvc_c_noh -- Halmir's Divine Champions branch: the "how does one
// come to stand among them" pointer for a PC who has not started the
// quest and has no Divine Champion level yet.
// (roadmap: divine-champion-quest)
#include "q_dvc_inc"

int StartingConditional()
{
    object oPC = GetPCSpeaker();
    return QDVC_GetStage(oPC) == QDVC_STAGE_NONE
        && !QDVC_IsDivineChampion(oPC);
}
