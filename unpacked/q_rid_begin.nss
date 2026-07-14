// The Riddle Game (roadmap: riddle-game)
// ActionTaken when the PC accepts the wretch's challenge: reset the session
// locals, capture the week seed and open the journal. Guarded so a stale
// dialogue can never start a second game in a stamped week.
#include "q_rid_inc"

void main()
{
    object oPC = GetPCSpeaker();
    if (QCD_IsDoneThisWeek(oPC, QRID_QUEST)) return;
    if (GetLocalInt(oPC, "Q_RID_ACTIVE")) return;

    SetLocalInt(oPC, "Q_RID_ACTIVE", 1);
    SetLocalInt(oPC, "Q_RID_IDX", 0);
    SetLocalInt(oPC, "Q_RID_SCORE", 0);
    SetLocalInt(oPC, "Q_RID_SEED", QRID_WeekSeed());
    DeleteLocalInt(oPC, "Q_RID_LAST");
    DeleteLocalInt(oPC, "Q_RID_RESULT");

    AddJournalQuestEntry(QRID_QUEST, 1, oPC, FALSE, FALSE, TRUE);
}
