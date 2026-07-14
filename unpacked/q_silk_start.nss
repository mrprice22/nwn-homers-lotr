// Spider Silk Harvest (roadmap: spider-silk-harvest)
// ActionTaken when the PC accepts Thranduil's harvest. Stamps the
// accepted-today key (QS_ACC) — the persistent active flag the death hook
// reads — and opens the journal. Guarded against double-accept.
#include "q_silk_inc"

void main()
{
    object oPC = GetPCSpeaker();
    if (QCD_IsDoneToday(oPC, QS_QUEST) || QS_IsActive(oPC))
        return;
    QCD_Stamp(oPC, QS_ACC);
    AddJournalQuestEntry(QS_QUEST, 1, oPC, FALSE, FALSE, TRUE);
}
