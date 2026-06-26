// merit_mcanc_7 — Reply action: cancel the player's own pending request in slot 7.
#include "merit_redeem"
void main()
{
    object oPC = GetPCSpeaker();
    int nId = GetLocalInt(oPC, "merit_lslot_7");
    if (nId > 0)
        Merit_CancelRedemption(nId, GetPCPublicCDKey(oPC), GetPCPlayerName(oPC), FALSE);
    Merit_BuildMyPending(oPC);   // refresh the list
}
