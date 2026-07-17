// q_shf_start -- accept ActionTaken on Halmir's Shifters branch
// (roadmap: shifter-quest). Stage 0 -> 1 and journal entry 1. Nothing
// to spawn: the trial's objective is the existing still pool at Beorn's
// steading (beorn.git.json, tag ShfBeornPool).
#include "q_shf_inc"

void main()
{
    object oPC = GetPCSpeaker();
    if (QSHF_GetStage(oPC) != QSHF_STAGE_NONE) return;

    QSHF_SetStage(oPC, QSHF_STAGE_ACCEPTED);
    AddJournalQuestEntry(QSHF_QUEST, 1, oPC, FALSE, FALSE);
}
