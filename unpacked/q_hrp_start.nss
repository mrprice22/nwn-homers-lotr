// q_hrp_start — accept ActionTaken on Halmir's Harper branch
// (roadmap: harper-scout-quest). Stage 0 -> 1, journal entry 1, and make
// sure the contact stands at her table (cross-area spawn works: the
// waypoint is looked up module-wide).
#include "q_hrp_inc"

void main()
{
    object oPC = GetPCSpeaker();
    if (QHRP_GetStage(oPC) != QHRP_STAGE_NONE) return;

    QHRP_SetStage(oPC, QHRP_STAGE_ACCEPTED);
    AddJournalQuestEntry(QHRP_QUEST, 1, oPC, FALSE, FALSE);

    QHRP_SpawnContact();
}
