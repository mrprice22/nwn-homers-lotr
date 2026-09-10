// cp_master -- Crash Party: the master switch. Control-room placeable, OnUsed.
//
// Toggles CP_MODE, which gates the DISPENSER and nothing else. Turning the party
// off never touches an item already in a player's pack -- those keep working
// forever, which is the promise the event is sold on. Turning it off also resets
// the wave to 0 so the next party starts from the top.
//
// CP_MODE is a module LocalInt on purpose: a reboot always ends the party, which
// is the failsafe you want on an unattended box. dbg_combat.nss is the precedent.

#include "cp_dm_inc"

void main()
{
    object oPC = CP_DmUser();   // placard OR rest menu
    if (!CP_DmGate(oPC)) return;

    int bNew = !CP_IsOn();
    CP_SetMode(bNew);

    // Rewind the countdown so a second party starts from the top.
    DeleteLocalInt(GetModule(), "CP_ANN_STEP");

    SendMessageToPC(oPC, bNew
        ? "CRASH PARTY: ON. Wave 0 is live; favours are being handed out at the Well of Eru."
        : "CRASH PARTY: OFF. Dispenser closed, wave reset to 0. Nobody's items were touched.");
}
