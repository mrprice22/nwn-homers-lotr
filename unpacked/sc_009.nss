//::///////////////////////////////////////////////
//:: FileName sc_009
//:://////////////////////////////////////////////
//:://////////////////////////////////////////////
//:: Created By: Script Wizard
//:: Created On: 9/29/2002 3:41:16 PM
//:://////////////////////////////////////////////
int StartingConditional()
{
	// Ring chain complete (stage 2). Persistent "fret"/ring_stage replaces the
	// old non-persistent LocalInt "thugtest".
	return GetCampaignInt("fret", "ring_stage", GetPCSpeaker()) == 2;
}
