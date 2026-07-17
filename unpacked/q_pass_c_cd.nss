// Pass the Pass (roadmap: pass-the-pass)
// StartingConditional on the giver's "come back tomorrow" line: TRUE while the
// PC has already run today's escort. Sets token 6395 to the reset countdown.
#include "q_pass_inc"
int StartingConditional()
{
    object oPC = GetPCSpeaker();
    if (!QCD_IsDoneToday(oPC, QPASS_QUEST)) return FALSE;
    SetCustomToken(6395, QCD_FmtSpan(QPASS_SecsToTomorrow()));
    return TRUE;
}
