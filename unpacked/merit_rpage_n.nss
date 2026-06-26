// merit_rpage_n — Reply action: next page of pending redemptions.
#include "merit_redeem"
void main()
{
    object oDM = GetPCSpeaker();
    SetLocalInt(oDM, "merit_rpage_off", GetLocalInt(oDM, "merit_rpage_off") + 9);
    Merit_BuildPendingPage(oDM);
}
