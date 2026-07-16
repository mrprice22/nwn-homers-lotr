// q_wpm_c_noh -- Halmir's Weapon Masters branch: the "how does one come
// to be counted" pointer for a PC who has not started the quest and has
// no Weapon Master level yet. (roadmap: weapon-master-quest)
#include "q_wpm_inc"

int StartingConditional()
{
    object oPC = GetPCSpeaker();
    return QWPM_GetStage(oPC) == QWPM_STAGE_NONE && !QWPM_IsWeaponMaster(oPC);
}
