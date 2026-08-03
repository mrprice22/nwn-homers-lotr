// brd_vis_8 - conditional: show fallen-boss list row 8 only when populated.
int StartingConditional()
{
    return GetLocalString(GetPCSpeaker(), "brd_slot_8") != "";
}
