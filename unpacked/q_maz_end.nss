// q_maz_end - turn-in ActionTaken (roadmap: twentieth-plot-mazarbul).
// Frar's shade pays out: gold, XP and the Seal of the Twentieth, then the
// quest closes for good (stage 4, End=1). Hardened: only fires from stage
// 3, so the reward cannot be re-earned by re-running the dialogue.
#include "q_maz_inc"
#include "nw_i0_tool"

void main()
{
    object oPC = GetPCSpeaker();
    if (MAZ_GetStage(oPC) != 3)
        return;

    MAZ_SetStage(oPC, 4);
    SetCampaignInt(MAZ_DB, "done", 1, oPC);
    AddJournalQuestEntry(MAZ_QUEST, 4, oPC, FALSE, FALSE);

    RewardPartyGP(MAZ_GOLD, oPC, FALSE);
    RewardPartyXP(MAZ_XP, oPC, FALSE);
    CreateItemOnObject("q_maz_seal", oPC, 1);
    if (!GetIsObjectValid(GetItemPossessedBy(oPC, "q_maz_seal")))
        SendMessageToPC(oPC,
            "Your pack was full -- the Seal of the Twentieth lies at your feet.");
}
