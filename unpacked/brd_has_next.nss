// brd_has_next — conditional: show [Next page] only when more rows follow.
int StartingConditional()
{
    object oPC = GetPCSpeaker();
    return (GetLocalInt(oPC, "brd_page_off") + 9) < GetLocalInt(oPC, "brd_total");
}
