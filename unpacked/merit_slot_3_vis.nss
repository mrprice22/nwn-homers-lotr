// merit_slot_3_vis - Conditional: show slot 3 only when populated.
int StartingConditional()
{
    return GetLocalString(GetPCSpeaker(), "merit_slot_3_cdkey") != "";
}
