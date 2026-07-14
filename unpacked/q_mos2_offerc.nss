// The Miller's Other Son (roadmap: miller-other-son) -- StartingConditional
// for Han the Miller's sequel offer. Shown only when the original Bree
// Millers Son quest is complete (session-local "millerson" == 2, or the
// persistent mirror stamped by at_003.nss for characters who finished it
// after this quest shipped) and the sequel has not been started yet.
// Sequel state persists per character in the "mos2" campaign DB.
int StartingConditional()
{
    object oPC = GetPCSpeaker();
    if (GetCampaignInt("mos2", "stage", oPC) != 0)
        return FALSE;
    if (GetLocalInt(oPC, "millerson") == 2)
        return TRUE;
    return GetCampaignInt("mos2", "m1done", oPC) == 1;
}
