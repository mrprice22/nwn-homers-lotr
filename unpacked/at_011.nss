//::///////////////////////////////////////////////
//:: FileName at_011
//:://////////////////////////////////////////////
//:://////////////////////////////////////////////
//:: Created By: Script Wizard
//:: Created On: 9/25/2002 9:49:10 PM
//:://////////////////////////////////////////////
void main()
{
	// Set the variables
	SetLocalInt(GetPCSpeaker(), "glorquestgiven", 1);

	// Journal: quest accepted
	AddJournalQuestEntry("glorfindel_potion", 1, GetPCSpeaker(), FALSE, FALSE);

}
