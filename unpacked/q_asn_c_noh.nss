// q_asn_c_noh -- Halmir's Assassins branch: the "how does one come to be
// counted" pointer for a PC who has not started the quest and has no
// Assassin level yet. (roadmap: assassin-quest)
#include "q_asn_inc"

int StartingConditional()
{
    object oPC = GetPCSpeaker();
    return QASN_GetStage(oPC) == QASN_STAGE_NONE && !QASN_IsAssassin(oPC);
}
