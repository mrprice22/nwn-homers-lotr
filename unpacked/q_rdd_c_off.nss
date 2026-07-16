// q_rdd_c_off -- Halmir's Red Dragon Disciples branch: show the trial
// offer only to a PC who has not started the quest AND already carries
// the inheritance (1+ Red Dragon Disciple level -- the design gate).
// (roadmap: red-dragon-disciple-quest)
#include "q_rdd_inc"

int StartingConditional()
{
    object oPC = GetPCSpeaker();
    return QRDD_GetStage(oPC) == QRDD_STAGE_NONE && QRDD_IsDisciple(oPC);
}
