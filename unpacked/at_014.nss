//::///////////////////////////////////////////////
//:: FileName at_014
//:://////////////////////////////////////////////
//:://////////////////////////////////////////////
//:: Created By: Script Wizard
//:: Created On: 9/29/2002 3:28:11 PM
//:://////////////////////////////////////////////
void main()
{
	// Ferny's Ring intro accepted. Persist on "fret"/ring_qstart (was the
	// non-persistent LocalInt "queststart") so the intro state survives relog.
	SetCampaignInt("fret", "ring_qstart", 1, GetPCSpeaker());
}
