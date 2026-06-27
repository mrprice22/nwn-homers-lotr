// ru_vis_4 — conditional: show recent-updates list row 4 only when populated.
int StartingConditional()
{
    return GetLocalInt(GetPCSpeaker(), "ru_slot_4_rank") >= 0;
}
