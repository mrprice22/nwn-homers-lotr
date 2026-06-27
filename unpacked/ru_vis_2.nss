// ru_vis_2 — conditional: show recent-updates list row 2 only when populated.
int StartingConditional()
{
    return GetLocalInt(GetPCSpeaker(), "ru_slot_2_rank") >= 0;
}
