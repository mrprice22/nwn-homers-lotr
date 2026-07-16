// q_asn_start -- accept ActionTaken on Halmir's Assassins branch
// (roadmap: assassin-quest). Stage 0 -> 1 and journal entry 1. Nothing to
// spawn: the trial's objective is the existing dead-drop wine barrel in
// Bree (bree.git.json, tag AsnDeadDrop).
#include "q_asn_inc"

void main()
{
    object oPC = GetPCSpeaker();
    if (QASN_GetStage(oPC) != QASN_STAGE_NONE) return;

    QASN_SetStage(oPC, QASN_STAGE_ACCEPTED);
    AddJournalQuestEntry(QASN_QUEST, 1, oPC, FALSE, FALSE);
}
