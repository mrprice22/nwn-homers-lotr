// q_shd_start -- accept ActionTaken on Halmir's Shadowdancers branch
// (roadmap: shadowdancer-quest). Stage 0 -> 1 and journal entry 1.
// Nothing to spawn: the trial's objective is the existing Deep Well
// placeable beside Balin's tomb (balinstomb).
#include "q_shd_inc"

void main()
{
    object oPC = GetPCSpeaker();
    if (QSHD_GetStage(oPC) != QSHD_STAGE_NONE) return;

    QSHD_SetStage(oPC, QSHD_STAGE_ACCEPTED);
    AddJournalQuestEntry(QSHD_QUEST, 1, oPC, FALSE, FALSE);
}
