// brd_vis_4 - conditional: show fallen-boss list row 4 only when populated.
int StartingConditional()
{
    return GetLocalString(GetPCSpeaker(), "brd_slot_4") != "";
}
