// ru_has_prev - conditional: show [Previous page] only when past the first page.
int StartingConditional()
{
    return GetLocalInt(GetPCSpeaker(), "ru_page_off") > 0;
}
