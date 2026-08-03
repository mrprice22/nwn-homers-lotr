// q_kwn_banner - the Gate Captain releases the standard to the mustered
// detail (q_kwn_capt). Stage 3 -> 4, journal entry 4, and re-check the
// banner-stone spawn (in case the Pelennor has not been entered since the
// waypoint was placed). Hardened: only fires from stage 3.
// (roadmap: knight-westernesse-quest)
#include "q_kwn_inc"

void main()
{
    object oPC = GetPCSpeaker();
    if (QKWN_GetStage(oPC) != QKWN_STAGE_MUSTERED) return;

    QKWN_SetStage(oPC, QKWN_STAGE_STANDARD);
    AddJournalQuestEntry(QKWN_QUEST, 4, oPC, FALSE, FALSE);

    QKWN_SpawnStone();
}
