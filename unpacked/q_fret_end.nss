// Ferny's Return (roadmap: ferny-return) -- the Guardian of Bree pays out.
// Completes the quest (stage 3, End=1) and stamps the persistent prequel
// flag read by Ferny's Ring for its discount branch (q_fret_discc,
// endferny1.nss, aquirering.nss). Hardened: only fires from stage 2, so the
// reward cannot be re-earned by re-running the dialogue.
#include "nw_i0_tool"

void main()
{
    object oPC = GetPCSpeaker();
    if (GetCampaignInt("fret", "stage", oPC) != 2)
        return;

    SetCampaignInt("fret", "stage", 3, oPC);
    SetCampaignInt("fret", "done", 1, oPC);
    // Session-local mirror of the prequel flag (per the original design note);
    // persistent reads should use GetCampaignInt("fret", "done", oPC).
    SetLocalInt(oPC, "ferny_prequel", 1);
    AddJournalQuestEntry("ferny_return", 3, oPC, FALSE, FALSE);

    RewardPartyGP(200, oPC, FALSE);
    RewardPartyXP(250, oPC, FALSE);
    CreateItemOnObject("fret_glove", oPC, 1);
    if (!GetIsObjectValid(GetItemPossessedBy(oPC, "fret_glove")))
        SendMessageToPC(oPC, "Your pack was full -- the gloves lie at your feet.");
}
