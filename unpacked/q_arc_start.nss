// q_arc_start -- accept ActionTaken on Halmir's Arcane Archers branch
// (roadmap: arcane-archer-quest). Stage 0 -> 1 and journal entry 1.
// Nothing to spawn: the trial's objective is the existing archery target
// on Rivendell's training ground (rivendell, tag WardenMark).
#include "q_arc_inc"

void main()
{
    object oPC = GetPCSpeaker();
    if (QARC_GetStage(oPC) != QARC_STAGE_NONE) return;

    QARC_SetStage(oPC, QARC_STAGE_ACCEPTED);
    AddJournalQuestEntry(QARC_QUEST, 1, oPC, FALSE, FALSE);
}
