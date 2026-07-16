// q_asn_c_off -- Halmir's Assassins branch: show the trial offer only to
// a PC who has not started the quest AND already walks with the quiet
// knives (1+ Assassin level -- the design gate). (roadmap: assassin-quest)
#include "q_asn_inc"

int StartingConditional()
{
    object oPC = GetPCSpeaker();
    return QASN_GetStage(oPC) == QASN_STAGE_NONE && QASN_IsAssassin(oPC);
}
