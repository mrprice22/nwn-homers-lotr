// merit_has_next - Conditional: show [Next >>] only when more pages exist.
int StartingConditional()
{
    object oDM  = GetPCSpeaker();
    int nOff    = GetLocalInt(oDM, "merit_page_off");
    int nTotal  = GetLocalInt(oDM, "merit_page_total");
    return (nOff + 9) < nTotal;
}
