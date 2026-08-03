// bst_has_next - conditional: show [Next >>] only when more rows remain.
int StartingConditional()
{
    object oPC = GetPCSpeaker();
    return (GetLocalInt(oPC, "bst_page_off") + 9) < GetLocalInt(oPC, "bst_page_total");
}
