// brd_vis_3 — conditional: show fallen-boss list row 3 only when populated.
int StartingConditional()
{
    return GetLocalString(GetPCSpeaker(), "brd_slot_3") != "";
}
