// brd_vis_6 - conditional: show fallen-boss list row 6 only when populated.
int StartingConditional()
{
    return GetLocalString(GetPCSpeaker(), "brd_slot_6") != "";
}
