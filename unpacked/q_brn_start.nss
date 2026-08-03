// Beorn's Garden (roadmap: beorns-garden)
// ActionTaken when the PC takes on the day's garden work. Stamps the
// accepted-today key (BRN_ACC) - the persistent active flag the hive and
// warg hooks read - and opens the journal. Guarded against double-accept.
#include "q_brn_inc"

void main()
{
    object oPC = GetPCSpeaker();
    if (QCD_IsDoneToday(oPC, BRN_QUEST) || BRN_IsActive(oPC))
        return;
    QCD_Stamp(oPC, BRN_ACC);
    AddJournalQuestEntry(BRN_QUEST, 1, oPC, FALSE, FALSE, TRUE);
}
