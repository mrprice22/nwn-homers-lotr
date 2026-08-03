// merit_slot_6_vis - Conditional: show slot 6 only when populated.
int StartingConditional()
{
    return GetLocalString(GetPCSpeaker(), "merit_slot_6_cdkey") != "";
}
