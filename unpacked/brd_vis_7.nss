// brd_vis_7 — conditional: show fallen-boss list row 7 only when populated.
int StartingConditional()
{
    return GetLocalString(GetPCSpeaker(), "brd_slot_7") != "";
}
