// merit_dsel_5 - Reply action: select pending request in slot 5 for fulfil/cancel.
#include "merit_redeem"
void main()
{
    object oDM = GetPCSpeaker();
    SetLocalInt(oDM, "merit_dsel_id", GetLocalInt(oDM, "merit_lslot_5"));
    SetCustomToken(5038, GetLocalString(oDM, "merit_lslot_5_desc"));
}
