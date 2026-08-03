// merit_lvis_6 - Conditional: show list slot 6 only when populated.
int StartingConditional()
{
    return GetLocalInt(GetPCSpeaker(), "merit_lslot_6") > 0;
}
