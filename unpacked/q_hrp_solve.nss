// q_hrp_solve - fires on Della's counter-word line (q_hrp_conv), reached
// only after the cipher is read true (Lore shortcut or the hint path).
// Stage 1 -> 2, journal entry 2. Hardened: only fires from stage 1, so
// re-running the dialogue can't skip or repeat states.
// (roadmap: harper-scout-quest)
#include "q_hrp_inc"

void main()
{
    object oPC = GetPCSpeaker();
    if (QHRP_GetStage(oPC) != QHRP_STAGE_ACCEPTED) return;

    QHRP_SetStage(oPC, QHRP_STAGE_SOLVED);
    AddJournalQuestEntry(QHRP_QUEST, 2, oPC, FALSE, FALSE);
}
