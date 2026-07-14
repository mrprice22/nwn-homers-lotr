// The Miller's Other Son -- Han pays out the happy ending (Dob freed by
// word or by steel). Completes the quest (stage 3, End entry 6) and rewards
// 500 gp + 500 XP + a Magic Bag ("Dob's trading pack", stock
// nw_it_contain004). Hardened: only fires from stage 2 with a freed-boy
// outcome, so the reward cannot be re-earned by re-running the dialogue.
#include "nw_i0_tool"

void main()
{
    object oPC = GetPCSpeaker();
    if (GetCampaignInt("mos2", "stage", oPC) != 2)
        return;
    int nOutcome = GetCampaignInt("mos2", "outcome", oPC);
    if (nOutcome != 1 && nOutcome != 2)
        return;

    SetCampaignInt("mos2", "stage", 3, oPC);
    SetCampaignInt("mos2", "done", 1, oPC);
    AddJournalQuestEntry("bree_miller_son2", 6, oPC, FALSE, FALSE);

    RewardPartyGP(500, oPC, FALSE);
    RewardPartyXP(500, oPC, FALSE);
    CreateItemOnObject("nw_it_contain004", oPC, 1);
}
