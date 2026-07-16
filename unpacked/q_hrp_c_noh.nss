// q_hrp_c_noh — Halmir's Harper branch: the "how does one join" pointer for
// a PC who has not started the quest and has no Harper Scout level yet.
// (roadmap: harper-scout-quest)
#include "q_hrp_inc"

int StartingConditional()
{
    object oPC = GetPCSpeaker();
    return QHRP_GetStage(oPC) == QHRP_STAGE_NONE && !QHRP_IsHarper(oPC);
}
