//::///////////////////////////////////////////////
//:: FileName aquirering
//:://////////////////////////////////////////////
//:://////////////////////////////////////////////
//:: Created By: Script Wizard
//:: Created On: 9/15/2002 4:22:35 PM
//:://////////////////////////////////////////////
#include "nw_i0_tool"

void main()
{
	object oPC = GetPCSpeaker();

	// Ferny's Ring turn-in. Gate on the persistent ring_stage (campaign DB
	// "fret") so relogging can't lose progress or re-grant the reward -- the
	// old per-PC LocalInt "thugtest" was wiped on every logout/reboot.
	if (GetCampaignInt("fret", "ring_stage", oPC) != 0)
		return;

	// Give the speaker some XP
	RewardPartyXP(500, oPC);


	// Remove items from the player's inventory
	object oItemToTake;
	oItemToTake = GetItemPossessedBy(oPC, "RingofSharkey");
	if(GetIsObjectValid(oItemToTake) != 0)
		DestroyObject(oItemToTake);
	// Advance the persistent ring-chain stage (was LocalInt "thugtest")
	SetCampaignInt("fret", "ring_stage", 1, oPC);

	// Ferny's Return prequel bonus: Ferny pays half again to the one who
	// cleared the Sharkey squatter out of his house (see q_fret_end.nss).
	if (GetCampaignInt("fret", "done", GetPCSpeaker()))
	{
		GiveGoldToCreature(GetPCSpeaker(), 100);
		SendMessageToPC(GetPCSpeaker(),
			"Ferny counts out extra coin -- payment for clearing the rat out of his house.");
	}
}
