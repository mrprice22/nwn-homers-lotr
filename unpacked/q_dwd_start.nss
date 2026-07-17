// q_dwd_start -- accept ActionTaken on Halmir's Dwarven Defenders branch
// (roadmap: dwarven-defender-quest). Stage 0 -> 1 and journal entry 1.
// Nothing to spawn: the stand's objective is the existing headstone of
// Balin in Balin's Tomb (balinstomb.git.json, tag DwdBalinStone).
#include "q_dwd_inc"

void main()
{
    object oPC = GetPCSpeaker();
    if (QDWD_GetStage(oPC) != QDWD_STAGE_NONE) return;

    QDWD_SetStage(oPC, QDWD_STAGE_ACCEPTED);
    AddJournalQuestEntry(QDWD_QUEST, 1, oPC, FALSE, FALSE);
}
