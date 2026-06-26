// merit_rpage_p — Reply action: previous page of pending redemptions.
#include "merit_redeem"
void main()
{
    object oDM = GetPCSpeaker();
    int nOff = GetLocalInt(oDM, "merit_rpage_off") - 9;
    if (nOff < 0) nOff = 0;
    SetLocalInt(oDM, "merit_rpage_off", nOff);
    Merit_BuildPendingPage(oDM);
}
