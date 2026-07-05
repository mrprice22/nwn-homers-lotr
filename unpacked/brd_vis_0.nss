// brd_vis_0 — conditional: show fallen-boss list row 0 only when populated.
int StartingConditional()
{
    return GetLocalString(GetPCSpeaker(), "brd_slot_0") != "";
}
