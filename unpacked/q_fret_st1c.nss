// Ferny's Return -- StartingConditional: quest accepted, impostor not yet
// dealt with (stage 1). Used by both the guard's reminder greeting and the
// impostor's confrontation opener.
int StartingConditional()
{
    return GetCampaignInt("fret", "stage", GetPCSpeaker()) == 1;
}
