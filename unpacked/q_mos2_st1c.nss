// The Miller's Other Son -- StartingConditional: quest accepted, son not yet
// dealt with (stage 1). Used by the miller's reminder greeting, the
// peddler's quest greeting, and the cult leader's confrontation opener.
int StartingConditional()
{
    return GetCampaignInt("mos2", "stage", GetPCSpeaker()) == 1;
}
