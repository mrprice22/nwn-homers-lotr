// merit_thas_next - Conditional: show [Next >>] in the tournament picker.
int StartingConditional()
{
    object oPC = GetPCSpeaker();
    return GetLocalInt(oPC, "merit_pick_id") == 302
        && (GetLocalInt(oPC, "merit_tpage_off") + 9) < GetLocalInt(oPC, "merit_tpage_total");
}
