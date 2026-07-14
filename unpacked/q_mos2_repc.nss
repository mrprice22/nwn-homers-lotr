// The Miller's Other Son -- StartingConditional: the matter at the cult camp
// is settled one way or another (stage 2), ready to report back to Han.
int StartingConditional()
{
    return GetCampaignInt("mos2", "stage", GetPCSpeaker()) == 2;
}
