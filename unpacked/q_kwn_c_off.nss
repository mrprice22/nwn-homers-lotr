// q_kwn_c_off — Halmir's Westernesse branch: show the proving offer only
// to a PC who has not started the quest AND already rides in the order's
// line (1+ Knight of Westernesse level — the design gate).
// (roadmap: knight-westernesse-quest)
#include "q_kwn_inc"

int StartingConditional()
{
    object oPC = GetPCSpeaker();
    return QKWN_GetStage(oPC) == QKWN_STAGE_NONE && QKWN_IsKnight(oPC);
}
