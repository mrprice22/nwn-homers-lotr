// merit_thas_prev — Conditional: show [<< Previous] in the tournament picker.
int StartingConditional()
{
    object oPC = GetPCSpeaker();
    return GetLocalInt(oPC, "merit_pick_id") == 302
        && GetLocalInt(oPC, "merit_tpage_off") > 0;
}
