// Ferny's Return -- OnDeath for the impostor (fret_impostor.utc). Advances
// every party-member PC in the area who is at stage 1 to stage 2 with
// outcome "fought". Quest state lives in the "fret" campaign DB per
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
        if (GetArea(oMember) == oArea
            && GetCampaignInt("fret", "stage", oMember) == 1)
        {
            SetCampaignInt("fret", "stage", 2, oMember);
            SetCampaignInt("fret", "outcome", 1, oMember);
            AddJournalQuestEntry("ferny_return", 2, oMember, FALSE, FALSE);
        }
        oMember = GetNextFactionMember(oKiller, TRUE);
    }
}
