// The Miller's Other Son -- the sad truth: the player left Dob with the
// cult and tells Han so. Completes the quest (stage 3, End entry 7) with a
// smaller reward -- honesty pays, but not well. Hardened against re-runs.
#include "nw_i0_tool"

void main()
{
    object oPC = GetPCSpeaker();
    if (GetCampaignInt("mos2", "stage", oPC) != 2)
        return;
    if (GetCampaignInt("mos2", "outcome", oPC) != 3)
        return;

    SetCampaignInt("mos2", "stage", 3, oPC);
    SetCampaignInt("mos2", "done", 1, oPC);
    AddJournalQuestEntry("bree_miller_son2", 7, oPC, FALSE, FALSE);

    RewardPartyXP(200, oPC, FALSE);
}
