// merit_slot_2_vis - Conditional: show slot 2 only when populated.
int StartingConditional()
{
    return GetLocalString(GetPCSpeaker(), "merit_slot_2_cdkey") != "";
}
