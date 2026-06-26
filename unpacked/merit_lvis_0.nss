// merit_lvis_0 — Conditional: show list slot 0 only when populated.
int StartingConditional()
{
    return GetLocalInt(GetPCSpeaker(), "merit_lslot_0") > 0;
}
