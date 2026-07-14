// The Miller's Other Son -- StartingConditional for the Persuade reply.
// One attempt per character, ever: shown only at stage 1 and only if the
// attempt has not been spent (persistent "tried" flag, campaign DB "mos2").
int StartingConditional()
{
    object oPC = GetPCSpeaker();
    if (GetCampaignInt("mos2", "stage", oPC) != 1)
        return FALSE;
    return GetCampaignInt("mos2", "tried", oPC) == 0;
}
