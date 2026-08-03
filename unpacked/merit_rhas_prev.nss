// merit_rhas_prev - Conditional: show [<< Previous] only when not on page 1.
int StartingConditional()
{
    return GetLocalInt(GetPCSpeaker(), "merit_rpage_off") > 0;
}
