// merit_slot_7_vis - Conditional: show slot 7 only when populated.
int StartingConditional()
{
    return GetLocalString(GetPCSpeaker(), "merit_slot_7_cdkey") != "";
}
