// q_dvc_start -- accept ActionTaken on Halmir's Divine Champions branch
// (roadmap: divine-champion-quest). Stage 0 -> 1 and journal entry 1.
// Nothing to spawn: the vigil's objective is the existing Altar of the
// Istari in the Minas Tirith temple (minastirithtemp.git.json, tag
// DvcVigilAltar).
#include "q_dvc_inc"

void main()
{
    object oPC = GetPCSpeaker();
    if (QDVC_GetStage(oPC) != QDVC_STAGE_NONE) return;

    QDVC_SetStage(oPC, QDVC_STAGE_ACCEPTED);
    AddJournalQuestEntry(QDVC_QUEST, 1, oPC, FALSE, FALSE);
}
