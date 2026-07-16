// q_arc_c_prog -- TRUE while the trial is under way (stages 1-2):
// Halmir's reminder line. Listed after q_arc_c_rdy on the branch, so it
// only shows when the turn-in line does not (no shaft in hand yet, or
// the shaft was lost -- the mark re-gives it). (roadmap: arcane-archer-quest)
#include "q_arc_inc"

int StartingConditional()
{
    int nStage = QARC_GetStage(GetPCSpeaker());
    return nStage >= QARC_STAGE_ACCEPTED && nStage <= QARC_STAGE_SHAFT;
}
