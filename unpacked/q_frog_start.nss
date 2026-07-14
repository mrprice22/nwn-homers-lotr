// The Last Drop at Frogmorton Inn (roadmap: frogmorton-last-drop)
// ActionTaken on the "what's all that about?" reply in Rigrin's conversation
// (store041.dlg). Re-adds journal stage 1 for the day's puzzle unless the PC
// has already judged today. bAllowOverrideHigher lets the daily re-open the
// journal after yesterday's End=1 stage 2.
#include "quest_cd_inc"

void main()
{
    object oPC = GetPCSpeaker();
    if (QCD_IsDoneToday(oPC, "frogmorton_ale"))
        return;
    AddJournalQuestEntry("frogmorton_ale", 1, oPC, FALSE, FALSE, TRUE);
}
