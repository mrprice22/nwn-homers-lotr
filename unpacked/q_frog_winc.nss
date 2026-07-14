// The Last Drop at Frogmorton Inn (roadmap: frogmorton-last-drop)
// StartingConditional: did the PC name this month's rightful drinker?
// FROG_PICK (1..5) is set by q_frog_pick1..5 on the answer replies; the
// correct claimant rotates monthly: ((GetCalendarMonth()-1) % 5) + 1.
// Keep the mapping in sync with q_frog_rulec.nss.

int StartingConditional()
{
    object oPC = GetPCSpeaker();
    int nCorrect = ((GetCalendarMonth() - 1) % 5) + 1;
    return GetLocalInt(oPC, "FROG_PICK") == nCorrect;
}
