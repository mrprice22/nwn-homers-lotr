// q_arc_c_noh -- Halmir's Arcane Archers branch: the "how does one come
// to that craft" pointer for a PC who has not started the quest and has
// no Arcane Archer level yet. (roadmap: arcane-archer-quest)
#include "q_arc_inc"

int StartingConditional()
{
    object oPC = GetPCSpeaker();
    return QARC_GetStage(oPC) == QARC_STAGE_NONE && !QARC_IsArcher(oPC);
}
