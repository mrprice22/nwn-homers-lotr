// Concerning Hobbits (roadmap: concerning-hobbits)
// ActionTaken when the PC accepts Odo's challenge: reset the session locals,
// capture the season seed and open the journal. Guarded so a stale dialogue
// can never start a second game on a stamped day.
#include "q_hob_inc"

void main()
{
    object oPC = GetPCSpeaker();
    if (QCD_IsDoneToday(oPC, QHOB_QUEST)) return;
    if (GetLocalInt(oPC, "Q_HOB_ACTIVE")) return;

    SetLocalInt(oPC, "Q_HOB_ACTIVE", 1);
    SetLocalInt(oPC, "Q_HOB_IDX", 0);
    SetLocalInt(oPC, "Q_HOB_SCORE", 0);
    SetLocalInt(oPC, "Q_HOB_SEED", QHOB_SeasonSeed());
    DeleteLocalInt(oPC, "Q_HOB_LAST");
    DeleteLocalInt(oPC, "Q_HOB_RESULT");

    AddJournalQuestEntry(QHOB_QUEST, 1, oPC, FALSE, FALSE, TRUE);
}
