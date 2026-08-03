// q_kwn_c_noh - Halmir's Westernesse branch: the "how does one ride under
// that banner" pointer for a PC who has not started the quest and has no
// Knight of Westernesse level yet. (roadmap: knight-westernesse-quest)
#include "q_kwn_inc"

int StartingConditional()
{
    object oPC = GetPCSpeaker();
    return QKWN_GetStage(oPC) == QKWN_STAGE_NONE && !QKWN_IsKnight(oPC);
}
