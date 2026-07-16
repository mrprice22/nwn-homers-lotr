// q_pal_c_off -- Halmir's Pale-Masters branch: show the rite offer only
// to a PC who has not started the quest AND already reads the pale page
// (1+ Pale Master level -- the design gate). (roadmap: pale-master-quest)
#include "q_pal_inc"

int StartingConditional()
{
    object oPC = GetPCSpeaker();
    return QPAL_GetStage(oPC) == QPAL_STAGE_NONE && QPAL_IsPale(oPC);
}
