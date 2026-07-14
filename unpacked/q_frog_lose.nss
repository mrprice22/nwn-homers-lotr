// The Last Drop at Frogmorton Inn (roadmap: frogmorton-last-drop)
// ActionTaken on Rigrin's wrong-answer entry: one judgment per day -- a bad
// call still closes the journal and stamps the daily cooldown (no reward).
#include "quest_cd_inc"

void main()
{
    object oPC = GetPCSpeaker();
    DeleteLocalInt(oPC, "FROG_PICK");

    if (QCD_IsDoneToday(oPC, "frogmorton_ale"))
        return;
    QCD_Stamp(oPC, "frogmorton_ale");

    AddJournalQuestEntry("frogmorton_ale", 2, oPC, FALSE, FALSE, TRUE);
}
