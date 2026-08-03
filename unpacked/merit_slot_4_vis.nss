// merit_slot_4_vis - Conditional: show slot 4 only when populated.
int StartingConditional()
{
    return GetLocalString(GetPCSpeaker(), "merit_slot_4_cdkey") != "";
}
