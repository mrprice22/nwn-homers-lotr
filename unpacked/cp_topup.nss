// cp_topup -- penguin conversation action: hand over any released items this
// character has not had yet.
//
// The same catch-up call the Well of Eru entry makes, offered by hand so a
// crasher standing next to the penguin when a wave drops does not have to walk
// out of the area and back in.
#include "cp_inc"

void main()
{
    object oPC = GetPCSpeaker();
    if (!GetIsObjectValid(oPC) || !GetIsPC(oPC)) return;

    if (CP_GrantUpToWave(oPC) == 0)
        SendMessageToPC(oPC, "You already have everything the penguin is handing out.");
}
