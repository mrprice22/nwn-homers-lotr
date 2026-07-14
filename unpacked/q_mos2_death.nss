// The Miller's Other Son -- OnDeath for the cult leader (mos2_leader.utc).
// Advances every party-member PC in the area who is mid-quest (stage 1, or
// stage 2 after walking away) to stage 2 with outcome "fought" -- the boy is
// cut loose from the camp. Quest state lives in the "mos2" campaign DB per
// character, so it survives relogs and reboots.
void main()
{
    object oKiller = GetLastKiller();
    if (!GetIsPC(oKiller))
        oKiller = GetMaster(oKiller);
    if (!GetIsPC(oKiller))
        return;

    object oArea = GetArea(OBJECT_SELF);
    object oMember = GetFirstFactionMember(oKiller, TRUE);
    while (GetIsObjectValid(oMember))
    {
        if (GetArea(oMember) == oArea)
        {
            int nStage = GetCampaignInt("mos2", "stage", oMember);
            int nOutcome = GetCampaignInt("mos2", "outcome", oMember);
            if (nStage == 1 || (nStage == 2 && nOutcome == 3))
            {
                SetCampaignInt("mos2", "stage", 2, oMember);
                SetCampaignInt("mos2", "outcome", 2, oMember);
                AddJournalQuestEntry("bree_miller_son2", 4, oMember, FALSE, FALSE);
            }
        }
        oMember = GetNextFactionMember(oKiller, TRUE);
    }
}
