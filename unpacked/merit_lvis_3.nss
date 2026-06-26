// merit_lvis_3 — Conditional: show list slot 3 only when populated.
int StartingConditional()
{
    return GetLocalInt(GetPCSpeaker(), "merit_lslot_3") > 0;
}
