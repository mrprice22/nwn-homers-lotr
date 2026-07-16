// q_shd_c_noh -- Halmir's Shadowdancers branch: the "how does one come
// to walk that road" pointer for a PC who has not started the quest and
// has no Shadowdancer level yet. (roadmap: shadowdancer-quest)
#include "q_shd_inc"

int StartingConditional()
{
    object oPC = GetPCSpeaker();
    return QSHD_GetStage(oPC) == QSHD_STAGE_NONE && !QSHD_IsShadow(oPC);
}
