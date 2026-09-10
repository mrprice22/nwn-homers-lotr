// cp_optout -- penguin conversation action: give the party gear back and release
// this account's slot.
//
// Order matters: take the items FIRST, then clear the database. If the database
// went first and the item sweep then failed, the account would be free to sign a
// second character up while this one still had a full set -- which is the exact
// hole the whole opt-in mechanism exists to close.
#include "cp_inc"

void main()
{
    object oPC = GetPCSpeaker();
    if (!GetIsObjectValid(oPC) || !GetIsPC(oPC)) return;
    if (!CP_IsCrasher(oPC)) return;   // the reply should not have been offered

    int nTaken = CP_ReclaimItems(oPC);
    CP_OptOut(oPC);

    SendMessageToPC(oPC,
        "The penguin takes back " + IntToString(nTaken) + " item(s). Your account "
        + "is free again - any of your characters can sign up, including this one.");
}
