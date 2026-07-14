//::///////////////////////////////////////////////
//:: FileName at_003
//:://////////////////////////////////////////////
//:://////////////////////////////////////////////
//:: Created By: Script Wizard
//:: Created On: 11/11/2002 11:03:54 AM
//:://////////////////////////////////////////////
#include "nw_i0_tool"

void main()
{
	// Give the speaker some XP
	RewardPartyXP(450, GetPCSpeaker());

	// Set the variables
	SetLocalInt(GetPCSpeaker(), "millerson", 2);

	// Persistent mirror of "Bree Millers Son complete" for the sequel quest
	// The Miller's Other Son (roadmap: miller-other-son) -- the local int
	// above does not survive a relog, this campaign flag does.
	SetCampaignInt("mos2", "m1done", 1, GetPCSpeaker());
}
