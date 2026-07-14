// The Miller's Other Son -- StartingConditional: the cult leader was slain
// (outcome 2). Selects the "freed by force" report line.
int StartingConditional()
{
    return GetCampaignInt("mos2", "outcome", GetPCSpeaker()) == 2;
}
