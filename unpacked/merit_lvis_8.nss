// merit_lvis_8 - Conditional: show list slot 8 only when populated.
int StartingConditional()
{
    return GetLocalInt(GetPCSpeaker(), "merit_lslot_8") > 0;
}
