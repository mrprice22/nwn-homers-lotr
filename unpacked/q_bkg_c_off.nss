// q_bkg_c_off -- Halmir's Blackguards branch: show the fall-rite offer
// only to a PC who has not started the quest AND has already broken a
// bright oath for a darker one (1+ Blackguard level -- the design gate).
// (roadmap: blackguard-quest)
#include "q_bkg_inc"

int StartingConditional()
{
    object oPC = GetPCSpeaker();
    return QBKG_GetStage(oPC) == QBKG_STAGE_NONE
        && QBKG_IsBlackguard(oPC);
}
