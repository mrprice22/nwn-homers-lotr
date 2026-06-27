// ru_vis_0 — conditional: show recent-updates list row 0 only when populated.
int StartingConditional()
{
    return GetLocalInt(GetPCSpeaker(), "ru_slot_0_rank") >= 0;
}
