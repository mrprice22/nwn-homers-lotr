// merit_dsel_8 - Reply action: select pending request in slot 8 for fulfil/cancel.
#include "merit_redeem"
void main()
{
    object oDM = GetPCSpeaker();
    SetLocalInt(oDM, "merit_dsel_id", GetLocalInt(oDM, "merit_lslot_8"));
    SetCustomToken(5038, GetLocalString(oDM, "merit_lslot_8_desc"));
}
