// brd_vis_2 - conditional: show fallen-boss list row 2 only when populated.
int StartingConditional()
{
    return GetLocalString(GetPCSpeaker(), "brd_slot_2") != "";
}
