// merit_rcancel — Reply action: cancel the selected redemption (refunds the player).
#include "merit_redeem"
void main()
{
    object oDM = GetPCSpeaker();
    int nId = GetLocalInt(oDM, "merit_dsel_id");
    if (nId > 0)
        Merit_CancelRedemption(nId, GetPCPublicCDKey(oDM), GetPCPlayerName(oDM), TRUE);
    Merit_BuildPendingPage(oDM);   // refresh list
}
