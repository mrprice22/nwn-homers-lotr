// merit_slot_0_vis - Conditional: show slot 0 only when populated.
int StartingConditional()
{
    return GetLocalString(GetPCSpeaker(), "merit_slot_0_cdkey") != "";
}
