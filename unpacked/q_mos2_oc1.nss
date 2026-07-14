// The Miller's Other Son -- StartingConditional: the cult leader was talked
// down (outcome 1, Persuade). Selects the peaceful report line.
int StartingConditional()
{
    return GetCampaignInt("mos2", "outcome", GetPCSpeaker()) == 1;
}
