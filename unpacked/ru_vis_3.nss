// ru_vis_3 - conditional: show recent-updates list row 3 only when populated.
int StartingConditional()
{
    return GetLocalInt(GetPCSpeaker(), "ru_slot_3_rank") >= 0;
}
