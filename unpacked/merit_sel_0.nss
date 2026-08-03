// merit_sel_0 - Reply action: select player in slot 0 for merit award.
void main()
{
    object oDM    = GetPCSpeaker();
    string sCdKey = GetLocalString(oDM, "merit_slot_0_cdkey");
    string sName  = GetLocalString(oDM, "merit_slot_0_name");
    SetLocalString(oDM, "merit_sel_cdkey", sCdKey);
    SetLocalString(oDM, "merit_sel_name",  sName);
    SetCustomToken(5011, sName);
}
