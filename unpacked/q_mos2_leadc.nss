// The Miller's Other Son -- StartingConditional for the cult leader's "back
// again?" opener: the player already walked away (stage 2, outcome 3). The
// only ways forward from here are steel or the door.
int StartingConditional()
{
    object oPC = GetPCSpeaker();
    return GetCampaignInt("mos2", "stage", oPC) == 2
        && GetCampaignInt("mos2", "outcome", oPC) == 3;
}
