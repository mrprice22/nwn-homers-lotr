// merit_dsel_0 — Reply action: select pending request in slot 0 for fulfil/cancel.
#include "merit_redeem"
void main()
{
    object oDM = GetPCSpeaker();
    SetLocalInt(oDM, "merit_dsel_id", GetLocalInt(oDM, "merit_lslot_0"));
    SetCustomToken(5038, GetLocalString(oDM, "merit_lslot_0_desc"));
}
