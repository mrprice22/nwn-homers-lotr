// ru_vis_1 - conditional: show recent-updates list row 1 only when populated.
int StartingConditional()
{
    return GetLocalInt(GetPCSpeaker(), "ru_slot_1_rank") >= 0;
}
