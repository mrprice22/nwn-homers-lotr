// merit_rfulfill - Reply action: mark the selected redemption fulfilled.
#include "merit_redeem"
#include "admin_db"
void main()
{
    object oDM = GetPCSpeaker();

    // Authoritative half of the merit gate. The _cdkeymerit conditional on the
    // EmoteWand link only hides the menu line; this is what actually refuses.
    if (!Admin_CanMerit(oDM))
    {
        SendMessageToPC(oDM, "[Merit] You are not authorised to do that.");
        return;
    }

    int nId = GetLocalInt(oDM, "merit_dsel_id");
    if (nId > 0) Merit_FulfillRedemption(nId, GetPCPlayerName(oDM));
    Merit_BuildPendingPage(oDM);   // refresh list
}
