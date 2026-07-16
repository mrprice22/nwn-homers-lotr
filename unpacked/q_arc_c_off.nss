// q_arc_c_off -- Halmir's Arcane Archers branch: show the trial offer
// only to a PC who has not started the quest AND has already bent the
// bow to the art (1+ Arcane Archer level -- the design gate).
// (roadmap: arcane-archer-quest)
#include "q_arc_inc"

int StartingConditional()
{
    object oPC = GetPCSpeaker();
    return QARC_GetStage(oPC) == QARC_STAGE_NONE && QARC_IsArcher(oPC);
}
