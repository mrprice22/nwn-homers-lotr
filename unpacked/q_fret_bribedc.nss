// Ferny's Return -- StartingConditional: the player took the impostor's
// bribe from Ferny's stash (outcome 2). Selects the evasive report line.
int StartingConditional()
{
    return GetCampaignInt("fret", "outcome", GetPCSpeaker()) == 2;
}
