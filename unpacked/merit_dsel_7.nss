// merit_dsel_7 - Reply action: select pending request in slot 7 for fulfil/cancel.
#include "merit_redeem"
void main()
{
    object oDM = GetPCSpeaker();
    SetLocalInt(oDM, "merit_dsel_id", GetLocalInt(oDM, "merit_lslot_7"));
    SetCustomToken(5038, GetLocalString(oDM, "merit_lslot_7_desc"));
}
