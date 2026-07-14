// The Miller's Other Son -- StartingConditional: the player walked away and
// left the boy with the cult (outcome 3). Selects the sad-truth report line.
int StartingConditional()
{
    return GetCampaignInt("mos2", "outcome", GetPCSpeaker()) == 3;
}
