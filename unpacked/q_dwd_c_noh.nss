// q_dwd_c_noh -- Halmir's Dwarven Defenders branch: the "how does one
// come to be written on that page" pointer for a PC who has not started
// the quest and does not yet qualify (no Dwarven Defender level, or not
// of Durin's folk). (roadmap: dwarven-defender-quest)
#include "q_dwd_inc"

int StartingConditional()
{
    object oPC = GetPCSpeaker();
    return QDWD_GetStage(oPC) == QDWD_STAGE_NONE
        && !QDWD_IsDwarvenDefender(oPC);
}
