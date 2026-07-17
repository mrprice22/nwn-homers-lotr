// q_bkg_c_noh -- Halmir's Blackguards branch: the "how does one come to be
// counted among them" pointer for a PC who has not started the quest and
// has no Blackguard level yet. (roadmap: blackguard-quest)
#include "q_bkg_inc"

int StartingConditional()
{
    object oPC = GetPCSpeaker();
    return QBKG_GetStage(oPC) == QBKG_STAGE_NONE
        && !QBKG_IsBlackguard(oPC);
}
