// The Twentieth Plot of Mazarbul (roadmap: twentieth-plot-mazarbul)
// ActionTaken when the PC takes up Frar's charge. Persists per character
// (campaign DB "maz20", same scheme as Ferny's Return) and opens the
// journal. Guarded against double-accept.
#include "q_maz_inc"

void main()
{
    object oPC = GetPCSpeaker();
    if (MAZ_GetStage(oPC) != 0)
        return;
    MAZ_SetStage(oPC, 1);
    AddJournalQuestEntry(MAZ_QUEST, 1, oPC, FALSE, FALSE);
}
