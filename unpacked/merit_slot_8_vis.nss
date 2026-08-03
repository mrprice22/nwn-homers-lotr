// merit_slot_8_vis - Conditional: show slot 8 only when populated.
int StartingConditional()
{
    return GetLocalString(GetPCSpeaker(), "merit_slot_8_cdkey") != "";
}
