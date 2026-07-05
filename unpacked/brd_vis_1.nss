// brd_vis_1 — conditional: show fallen-boss list row 1 only when populated.
int StartingConditional()
{
    return GetLocalString(GetPCSpeaker(), "brd_slot_1") != "";
}
