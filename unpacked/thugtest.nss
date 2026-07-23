//::///////////////////////////////////////////////
//:: FileName thugtest
//:://////////////////////////////////////////////
//:://////////////////////////////////////////////
//:: Created By: Script Wizard
//:: Created On: 9/15/2002 4:24:07 PM
//:://////////////////////////////////////////////
int StartingConditional()
{
	// Ring chain reached stage 1 (ring turned in, orders not yet). Persistent
	// "fret"/ring_stage replaces the old non-persistent LocalInt "thugtest".
	return GetCampaignInt("fret", "ring_stage", GetPCSpeaker()) == 1;
}
