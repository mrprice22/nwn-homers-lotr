// ru_has_next - conditional: show [Next page] only when more rows follow.
int StartingConditional()
{
    object oPC = GetPCSpeaker();
    return (GetLocalInt(oPC, "ru_page_off") + 5) < GetLocalInt(oPC, "ru_total");
}
