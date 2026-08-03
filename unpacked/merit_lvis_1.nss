// merit_lvis_1 - Conditional: show list slot 1 only when populated.
int StartingConditional()
{
    return GetLocalInt(GetPCSpeaker(), "merit_lslot_1") > 0;
}
