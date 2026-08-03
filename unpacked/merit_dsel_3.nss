// merit_dsel_3 - Reply action: select pending request in slot 3 for fulfil/cancel.
#include "merit_redeem"
void main()
{
    object oDM = GetPCSpeaker();
    SetLocalInt(oDM, "merit_dsel_id", GetLocalInt(oDM, "merit_lslot_3"));
    SetCustomToken(5038, GetLocalString(oDM, "merit_lslot_3_desc"));
}
