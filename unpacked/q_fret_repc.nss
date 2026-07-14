// Ferny's Return -- StartingConditional: impostor dealt with (stage 2),
// ready to report back to the Guardian of Bree.
int StartingConditional()
{
    return GetCampaignInt("fret", "stage", GetPCSpeaker()) == 2;
}
