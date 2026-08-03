// deletetoon - NWNX:EE port (was: NWNX2 DELETECHAR IPC).
// Deletes the speaking PC's character on a 5-second delay.

#include "nwnx_admin"

void DoDelete(object oPC)
{
    if (!GetIsObjectValid(oPC) || !GetIsPC(oPC)) return;
    ExportSingleCharacter(oPC);
    NWNX_Administration_DeletePlayerCharacter(oPC, FALSE);
}

void main()
{
    object oPC = GetPCSpeaker();
    ActionSpeakString("Deleting in 5 seconds....");
    DelayCommand(5.0, DoDelete(oPC));
}
