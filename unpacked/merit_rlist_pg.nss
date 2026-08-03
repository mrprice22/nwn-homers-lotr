// merit_rlist_pg - Reply action: open the DM pending-redemptions list (page 1).
#include "merit_redeem"
void main()
{
    object oDM = GetPCSpeaker();
    SetLocalInt(oDM, "merit_rpage_off", 0);
    Merit_BuildPendingPage(oDM);
}
