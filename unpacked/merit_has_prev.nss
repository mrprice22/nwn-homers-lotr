// merit_has_prev - Conditional: show [<< Previous] only when not on page 1.
int StartingConditional()
{
    return GetLocalInt(GetPCSpeaker(), "merit_page_off") > 0;
}
