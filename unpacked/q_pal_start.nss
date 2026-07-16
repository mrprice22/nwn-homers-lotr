// q_pal_start -- accept ActionTaken on Halmir's Pale-Masters branch
// (roadmap: pale-master-quest). Stage 0 -> 1 and journal entry 1.
// Nothing to spawn: the twenty-first tomb is an existing placed
// sarcophagus in breecryptlowerle.
#include "q_pal_inc"

void main()
{
    object oPC = GetPCSpeaker();
    if (QPAL_GetStage(oPC) != QPAL_STAGE_NONE) return;

    QPAL_SetStage(oPC, QPAL_STAGE_ACCEPTED);
    AddJournalQuestEntry(QPAL_QUEST, 1, oPC, FALSE, FALSE);
}
