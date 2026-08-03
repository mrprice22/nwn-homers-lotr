// merit_lvis_4 - Conditional: show list slot 4 only when populated.
int StartingConditional()
{
    return GetLocalInt(GetPCSpeaker(), "merit_lslot_4") > 0;
}
