// merit_slot_5_vis - Conditional: show slot 5 only when populated.
int StartingConditional()
{
    return GetLocalString(GetPCSpeaker(), "merit_slot_5_cdkey") != "";
}
