// q_wpm_start -- accept ActionTaken on Halmir's Weapon Masters branch
// (roadmap: weapon-master-quest). Stage 0 -> 1 and journal entry 1.
// Nothing to spawn: the trial's objective is the existing practice post
// in Minas Tirith (minastirith.git.json, tag WMTrialPost).
#include "q_wpm_inc"

void main()
{
    object oPC = GetPCSpeaker();
    if (QWPM_GetStage(oPC) != QWPM_STAGE_NONE) return;

    QWPM_SetStage(oPC, QWPM_STAGE_ACCEPTED);
    AddJournalQuestEntry(QWPM_QUEST, 1, oPC, FALSE, FALSE);
}
