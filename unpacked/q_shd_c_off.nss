// q_shd_c_off -- Halmir's Shadowdancers branch: show the trial offer
// only to a PC who has not started the quest AND already walks unlit
// (1+ Shadowdancer level -- the design gate). (roadmap: shadowdancer-quest)
#include "q_shd_inc"

int StartingConditional()
{
    object oPC = GetPCSpeaker();
    return QSHD_GetStage(oPC) == QSHD_STAGE_NONE && QSHD_IsShadow(oPC);
}
