// The Miller's Other Son -- Persuade success: the Voice of the Red Eye lets
// the boy go. Stage 2, outcome 1 (persuaded); Dob runs for Bree off-screen
// and the cult breaks camp -- the Voice slips away shortly after.
void main()
{
    object oPC = GetPCSpeaker();
    if (GetCampaignInt("mos2", "stage", oPC) == 1)
    {
        SetCampaignInt("mos2", "stage", 2, oPC);
        SetCampaignInt("mos2", "outcome", 1, oPC);
        AddJournalQuestEntry("bree_miller_son2", 3, oPC, FALSE, FALSE);
    }
    DestroyObject(OBJECT_SELF, 8.0);
}
