// q_rdd_start -- accept ActionTaken on Halmir's Red Dragon Disciples
// branch (roadmap: red-dragon-disciple-quest). Stage 0 -> 1 and journal
// entry 1. Nothing to spawn: the trial's objective is the existing Forge
// of Durin in the Lonely Mountain's main hall (lonelymountainma, tag
// DurinForge).
#include "q_rdd_inc"

void main()
{
    object oPC = GetPCSpeaker();
    if (QRDD_GetStage(oPC) != QRDD_STAGE_NONE) return;

    QRDD_SetStage(oPC, QRDD_STAGE_ACCEPTED);
    AddJournalQuestEntry(QRDD_QUEST, 1, oPC, FALSE, FALSE);
}
