// Ferny's Return -- StartingConditional: the impostor was exposed and slain
// (outcome 1). Selects the "he drew steel" report line.
int StartingConditional()
{
    return GetCampaignInt("fret", "outcome", GetPCSpeaker()) == 1;
}
