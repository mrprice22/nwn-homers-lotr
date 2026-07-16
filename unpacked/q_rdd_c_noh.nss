// q_rdd_c_noh -- Halmir's Red Dragon Disciples branch: the "how does one
// come to that inheritance" pointer for a PC who has not started the
// quest and has no Red Dragon Disciple level yet.
// (roadmap: red-dragon-disciple-quest)
#include "q_rdd_inc"

int StartingConditional()
{
    object oPC = GetPCSpeaker();
    return QRDD_GetStage(oPC) == QRDD_STAGE_NONE && !QRDD_IsDisciple(oPC);
}
