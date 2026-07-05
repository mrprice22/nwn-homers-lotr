// brd_vis_5 — conditional: show fallen-boss list row 5 only when populated.
int StartingConditional()
{
    return GetLocalString(GetPCSpeaker(), "brd_slot_5") != "";
}
