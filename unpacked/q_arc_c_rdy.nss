// q_arc_c_rdy -- TRUE once the PC carries the shaft at stage 2:
// Halmir's turn-in line (GetItemPossessedBy reagent check).
// (roadmap: arcane-archer-quest)
#include "q_arc_inc"

int StartingConditional()
{
    object oPC = GetPCSpeaker();
    return QARC_GetStage(oPC) == QARC_STAGE_SHAFT && QARC_HasShaft(oPC);
}
