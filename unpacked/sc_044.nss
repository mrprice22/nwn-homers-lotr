//::///////////////////////////////////////////////
//:: FileName sc_044
//:://////////////////////////////////////////////
//:://////////////////////////////////////////////
//:: Created By: Script Wizard
//:: Created On: 11/11/2002 11:08:57 AM
//:://////////////////////////////////////////////
int StartingConditional()
{
	// Ferny's Ring intro accepted (qstart 1). Persistent "fret"/ring_qstart
	// replaces the old non-persistent LocalInt "queststart".
	return GetCampaignInt("fret", "ring_qstart", GetPCSpeaker()) == 1;
}
