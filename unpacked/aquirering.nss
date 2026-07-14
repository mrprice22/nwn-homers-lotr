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
	// Give the speaker some XP
	RewardPartyXP(500, GetPCSpeaker());


	// Remove items from the player's inventory
	object oItemToTake;
	oItemToTake = GetItemPossessedBy(GetPCSpeaker(), "RingofSharkey");
	if(GetIsObjectValid(oItemToTake) != 0)
		DestroyObject(oItemToTake);
	// Set the variables
	SetLocalInt(GetPCSpeaker(), "thugtest", 1);

	// Ferny's Return prequel bonus: Ferny pays half again to the one who
	// cleared the Sharkey squatter out of his house (see q_fret_end.nss).
	if (GetCampaignInt("fret", "done", GetPCSpeaker()))
	{
		GiveGoldToCreature(GetPCSpeaker(), 100);
		SendMessageToPC(GetPCSpeaker(),
			"Ferny counts out extra coin -- payment for clearing the rat out of his house.");
	}
}
