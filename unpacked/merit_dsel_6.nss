// merit_dsel_6 — Reply action: select pending request in slot 6 for fulfil/cancel.
#include "merit_redeem"
void main()
{
    object oDM = GetPCSpeaker();
    SetLocalInt(oDM, "merit_dsel_id", GetLocalInt(oDM, "merit_lslot_6"));
    SetCustomToken(5038, GetLocalString(oDM, "merit_lslot_6_desc"));
}
