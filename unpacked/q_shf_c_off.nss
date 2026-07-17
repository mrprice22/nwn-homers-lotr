// q_shf_c_off -- Halmir's Shifters branch: show the offer of the trial
// only to a PC who has not started the quest AND has already worn
// another shape (1+ Shifter level -- the design gate).
// (roadmap: shifter-quest)
#include "q_shf_inc"

int StartingConditional()
{
    object oPC = GetPCSpeaker();
    return QSHF_GetStage(oPC) == QSHF_STAGE_NONE
        && QSHF_IsShifter(oPC);
}
