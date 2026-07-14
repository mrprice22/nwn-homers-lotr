// The Last Drop at Frogmorton Inn (roadmap: frogmorton-last-drop)
// ActionTaken on Rigrin's "Right you are!" entry: pay out the daily reward
// (25 gp + a Frogmorton Pint), close the journal for the day and stamp the
// questcddb cooldown. Guarded so it can never pay twice in one day.
#include "quest_cd_inc"

void main()
{
    object oPC = GetPCSpeaker();
    DeleteLocalInt(oPC, "FROG_PICK");

    if (QCD_IsDoneToday(oPC, "frogmorton_ale"))
        return;
    QCD_Stamp(oPC, "frogmorton_ale");

    AddJournalQuestEntry("frogmorton_ale", 2, oPC, FALSE, FALSE, TRUE);
    GiveGoldToCreature(oPC, 25);
    CreateItemOnObject("frogpint", oPC, 1);
}
