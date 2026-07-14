// The Last Drop at Frogmorton Inn (roadmap: frogmorton-last-drop)
// StartingConditional: TRUE while the PC has already judged the cask today
// (calendar-daily reset at UTC midnight, per quest_cd_inc). Sets token 6331
// to the time remaining for Rigrin's "come back in <CUSTOM6331>" line.
#include "quest_cd_inc"

int StartingConditional()
{
    object oPC = GetPCSpeaker();
    if (!QCD_IsDoneToday(oPC, "frogmorton_ale"))
        return FALSE;

    // QCD_IsDoneToday resets at UTC midnight -- time left until then.
    int nToMidnight = 86400 - (QCD_Now() % 86400);
    SetCustomToken(6331, QCD_FmtSpan(nToMidnight));
    return TRUE;
}
