// The Riddle Game (roadmap: riddle-game)
// StartingConditional on the "we played already" greeting: TRUE once the PC
// has played this calendar week (win or lose - QCD_IsDoneThisWeek resets at
// the start of the next ISO week, UTC). Sets token 6360 to the time left
// for the wretch's "come back when the week turns -- <CUSTOM6360>" line.
#include "q_rid_inc"

int StartingConditional()
{
    object oPC = GetPCSpeaker();
    if (!QCD_IsDoneThisWeek(oPC, QRID_QUEST))
        return FALSE;
    SetCustomToken(6360, QCD_FmtSpan(QRID_SecsToNextWeek()));
    return TRUE;
}
