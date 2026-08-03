// q_kwn_muster - the Gate Captain sets the command exercise (q_kwn_capt).
// Stage 1 -> 2, journal entry 2. Hardened: only fires from stage 1.
// (roadmap: knight-westernesse-quest)
#include "q_kwn_inc"

void main()
{
    object oPC = GetPCSpeaker();
    if (QKWN_GetStage(oPC) != QKWN_STAGE_ACCEPTED) return;

    QKWN_SetStage(oPC, QKWN_STAGE_MUSTER);
    AddJournalQuestEntry(QKWN_QUEST, 2, oPC, FALSE, FALSE);
}
