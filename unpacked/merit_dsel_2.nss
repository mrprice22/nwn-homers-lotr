// merit_dsel_2 - Reply action: select pending request in slot 2 for fulfil/cancel.
#include "merit_redeem"
void main()
{
    object oDM = GetPCSpeaker();
    SetLocalInt(oDM, "merit_dsel_id", GetLocalInt(oDM, "merit_lslot_2"));
    SetCustomToken(5038, GetLocalString(oDM, "merit_lslot_2_desc"));
}
