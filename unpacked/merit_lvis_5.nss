// merit_lvis_5 - Conditional: show list slot 5 only when populated.
int StartingConditional()
{
    return GetLocalInt(GetPCSpeaker(), "merit_lslot_5") > 0;
}
