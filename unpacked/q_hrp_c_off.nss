// q_hrp_c_off — Halmir's Harper branch: show the errand offer only to a PC
// who has not started the quest AND already walks the Harpers' road
// (1+ Harper Scout level — the design gate). (roadmap: harper-scout-quest)
#include "q_hrp_inc"

int StartingConditional()
{
    object oPC = GetPCSpeaker();
    return QHRP_GetStage(oPC) == QHRP_STAGE_NONE && QHRP_IsHarper(oPC);
}
