// q_wpm_c_off -- Halmir's Weapon Masters branch: show the trial offer
// only to a PC who has not started the quest AND whose hand is already
// sworn (1+ Weapon Master level -- the design gate).
// (roadmap: weapon-master-quest)
#include "q_wpm_inc"

int StartingConditional()
{
    object oPC = GetPCSpeaker();
    return QWPM_GetStage(oPC) == QWPM_STAGE_NONE && QWPM_IsWeaponMaster(oPC);
}
