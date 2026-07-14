// The Miller's Other Son (roadmap: miller-other-son) -- the player agrees to
// find Han's other son, Dob. Persists per character (campaign DB "mos2") and
// spawns the peddler and the cult leader at the admin-placed waypoints.
void main()
{
    object oPC = GetPCSpeaker();
    if (GetCampaignInt("mos2", "stage", oPC) == 0)
    {
        SetCampaignInt("mos2", "stage", 1, oPC);
        AddJournalQuestEntry("bree_miller_son2", 1, oPC, FALSE, FALSE);
    }
    ExecuteScript("q_mos2_spawn", OBJECT_SELF);
}
