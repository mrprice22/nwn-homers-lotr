// merit_rhas_next — Conditional: show [Next >>] only when more pending pages exist.
int StartingConditional()
{
    object oDM = GetPCSpeaker();
    return (GetLocalInt(oDM, "merit_rpage_off") + 9) < GetLocalInt(oDM, "merit_rpage_total");
}
