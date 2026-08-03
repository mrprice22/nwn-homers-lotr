// merit_sel_7 - Reply action: select player in slot 7 for merit award.
void main()
{
    object oDM    = GetPCSpeaker();
    string sCdKey = GetLocalString(oDM, "merit_slot_7_cdkey");
    string sName  = GetLocalString(oDM, "merit_slot_7_name");
    SetLocalString(oDM, "merit_sel_cdkey", sCdKey);
    SetLocalString(oDM, "merit_sel_name",  sName);
    SetCustomToken(5011, sName);
}
