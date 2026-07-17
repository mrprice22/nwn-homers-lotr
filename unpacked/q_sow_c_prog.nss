// q_sow_c_prog -- StartingConditional for Ferny's mid-job greeting
// (ferny_convo2): TRUE while the PC still carries at least one forged
// letter. (roadmap: sowing-discord-bree)
#include "q_sow_inc"

int StartingConditional()
{
    return QSOW_InProgress(GetPCSpeaker());
}
