// Hobbit Post (roadmap: hobbit-post)
// StartingConditional: TRUE while the PC has already delivered today
// (calendar-daily reset at UTC midnight). Sets token 6342 for Posco's
// "post's closed till <CUSTOM6342> from now" line.
#include "q_post_inc"

int StartingConditional()
{
    object oPC = GetPCSpeaker();
    if (!QCD_IsDoneToday(oPC, QP_QUEST))
        return FALSE;
    int nToMidnight = 86400 - (QCD_Now() % 86400);
    SetCustomToken(6342, QCD_FmtSpan(nToMidnight));
    return TRUE;
}
