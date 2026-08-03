// bst_has_prev - conditional: show [<< Previous] only when not on page 1.
int StartingConditional()
{
    return GetLocalInt(GetPCSpeaker(), "bst_page_off") > 0;
}
