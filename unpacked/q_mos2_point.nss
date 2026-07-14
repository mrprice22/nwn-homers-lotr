// The Miller's Other Son -- the peddler points the player to the Red Eye
// camp east of Tharbad Bridge. Journal entry 2 (stage stays 1 -- the hint is
// flavor, not a gate; the player can find the camp without it).
void main()
{
    object oPC = GetPCSpeaker();
    if (GetCampaignInt("mos2", "stage", oPC) == 1)
        AddJournalQuestEntry("bree_miller_son2", 2, oPC, FALSE, FALSE);
}
