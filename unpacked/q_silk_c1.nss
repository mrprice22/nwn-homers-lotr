// Spider Silk Harvest (roadmap: spider-silk-harvest)
// StartingConditional: TRUE while the PC has already been paid today
// (calendar-daily reset at UTC midnight). Sets token 6350 for Thranduil's
// "return in <CUSTOM6350>" line.
#include "q_silk_inc"

int StartingConditional()
{
    object oPC = GetPCSpeaker();
    if (!QCD_IsDoneToday(oPC, QS_QUEST))
        return FALSE;
    int nToMidnight = 86400 - (QCD_Now() % 86400);
    SetCustomToken(6350, QCD_FmtSpan(nToMidnight));
    return TRUE;
}
