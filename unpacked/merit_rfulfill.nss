// merit_rfulfill - Reply action: mark the selected redemption fulfilled.
#include "merit_redeem"
void main()
{
    object oDM = GetPCSpeaker();
    int nId = GetLocalInt(oDM, "merit_dsel_id");
    if (nId > 0) Merit_FulfillRedemption(nId, GetPCPlayerName(oDM));
    Merit_BuildPendingPage(oDM);   // refresh list
}
