//::///////////////////////////////////////////////
//:: FileName endferny1
//:://////////////////////////////////////////////
//:://////////////////////////////////////////////
//:: Created By: Script Wizard
//:: Created On: 9/15/2002 4:16:39 PM
//:://////////////////////////////////////////////
#include "nw_i0_tool"

void main()
{
    object oPC = GetPCSpeaker();

    // Orders turn-in. Gate on the persistent ring_stage (campaign DB "fret")
    // so the reward can't be lost to a mid-chain relog or re-earned after a
    // reboot -- the old per-PC LocalInt "thugtest" was non-persistent.
    if (GetCampaignInt("fret", "ring_stage", oPC) != 1)
        return;

    // Give the speaker some gold
    RewardPartyGP(200, oPC);

    // Give the speaker some XP
    RewardPartyXP(500, oPC);


    // Remove items from the player's inventory
    object oItemToTake;
    oItemToTake = GetItemPossessedBy(oPC, "SharkeysOrders");
    if(GetIsObjectValid(oItemToTake) != 0)
        DestroyObject(oItemToTake);
    // Advance the persistent ring-chain stage (was LocalInt "thugtest")
    SetCampaignInt("fret", "ring_stage", 2, oPC);

    // Ferny's Return prequel bonus: Ferny pays half again to the one who
    // cleared the Sharkey squatter out of his house (see q_fret_end.nss).
    if (GetCampaignInt("fret", "done", GetPCSpeaker()))
    {
        GiveGoldToCreature(GetPCSpeaker(), 100);
        SendMessageToPC(GetPCSpeaker(),
            "Ferny counts out extra coin -- payment for clearing the rat out of his house.");
    }
}
