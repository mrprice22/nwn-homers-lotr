// The Miller's Other Son -- the player walks away and leaves Dob with the
// cult. Stage 2, outcome 3 (abandoned). Killing the Voice later upgrades the
// outcome to "fought" via q_mos2_death, so a change of heart still counts.
void main()
{
    object oPC = GetPCSpeaker();
    if (GetCampaignInt("mos2", "stage", oPC) == 1)
    {
        SetCampaignInt("mos2", "stage", 2, oPC);
        SetCampaignInt("mos2", "outcome", 3, oPC);
        AddJournalQuestEntry("bree_miller_son2", 5, oPC, FALSE, FALSE);
    }
}
