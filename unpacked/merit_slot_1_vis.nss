// merit_slot_1_vis - Conditional: show slot 1 only when populated.
int StartingConditional()
{
    return GetLocalString(GetPCSpeaker(), "merit_slot_1_cdkey") != "";
}
