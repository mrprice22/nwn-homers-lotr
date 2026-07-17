// q_shf_c_noh -- Halmir's Shifters branch: the "how does one come to be
// written on that page" pointer for a PC who has not started the quest
// and does not yet qualify (no Shifter level). (roadmap: shifter-quest)
#include "q_shf_inc"

int StartingConditional()
{
    object oPC = GetPCSpeaker();
    return QSHF_GetStage(oPC) == QSHF_STAGE_NONE
        && !QSHF_IsShifter(oPC);
}
