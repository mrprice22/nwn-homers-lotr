// Concerning Hobbits (roadmap: concerning-hobbits)
// StartingConditional on the "we settled this already today" greeting: TRUE
// once the PC has played today (win or lose -- QCD_IsDoneToday resets at UTC
// midnight). Sets token 6420 to the time left for Odo's "come back tomorrow,
// <CUSTOM6420> from now" line.
#include "q_hob_inc"

int StartingConditional()
{
    object oPC = GetPCSpeaker();
    if (!QCD_IsDoneToday(oPC, QHOB_QUEST))
        return FALSE;
    SetCustomToken(6420, QCD_FmtSpan(QHOB_SecsToTomorrow()));
    return TRUE;
}
