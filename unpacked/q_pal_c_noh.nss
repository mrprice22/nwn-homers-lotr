// q_pal_c_noh -- Halmir's Pale-Masters branch: the "how does one come to
// read that page" pointer for a PC who has not started the quest and has
// no Pale Master level yet. (roadmap: pale-master-quest)
#include "q_pal_inc"

int StartingConditional()
{
    object oPC = GetPCSpeaker();
    return QPAL_GetStage(oPC) == QPAL_STAGE_NONE && !QPAL_IsPale(oPC);
}
