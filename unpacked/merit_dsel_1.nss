// merit_dsel_1 — Reply action: select pending request in slot 1 for fulfil/cancel.
#include "merit_redeem"
void main()
{
    object oDM = GetPCSpeaker();
    SetLocalInt(oDM, "merit_dsel_id", GetLocalInt(oDM, "merit_lslot_1"));
    SetCustomToken(5038, GetLocalString(oDM, "merit_lslot_1_desc"));
}
