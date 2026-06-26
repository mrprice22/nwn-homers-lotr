// merit_dsel_4 — Reply action: select pending request in slot 4 for fulfil/cancel.
#include "merit_redeem"
void main()
{
    object oDM = GetPCSpeaker();
    SetLocalInt(oDM, "merit_dsel_id", GetLocalInt(oDM, "merit_lslot_4"));
    SetCustomToken(5038, GetLocalString(oDM, "merit_lslot_4_desc"));
}
