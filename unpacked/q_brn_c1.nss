// Beorn's Garden (roadmap: beorns-garden)
// StartingConditional: TRUE while the PC has already been paid today
// (calendar-daily reset at UTC midnight). Sets token 6370 for Grimbeorn's
// "return in <CUSTOM6370>" line.
#include "q_brn_inc"

int StartingConditional()
{
    object oPC = GetPCSpeaker();
    if (!QCD_IsDoneToday(oPC, BRN_QUEST))
        return FALSE;
    int nToMidnight = 86400 - (QCD_Now() % 86400);
    SetCustomToken(6370, QCD_FmtSpan(nToMidnight));
    return TRUE;
}
