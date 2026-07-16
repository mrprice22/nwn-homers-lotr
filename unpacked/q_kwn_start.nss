// q_kwn_start — accept ActionTaken on Halmir's Westernesse branch
// (roadmap: knight-westernesse-quest). Stage 0 -> 1, journal entry 1, and
// make sure the banner-stone stands on the Pelennor (cross-area spawn
// works: the waypoint is looked up module-wide).
#include "q_kwn_inc"

void main()
{
    object oPC = GetPCSpeaker();
    if (QKWN_GetStage(oPC) != QKWN_STAGE_NONE) return;

    QKWN_SetStage(oPC, QKWN_STAGE_ACCEPTED);
    AddJournalQuestEntry(QKWN_QUEST, 1, oPC, FALSE, FALSE);

    QKWN_SpawnStone();
}
