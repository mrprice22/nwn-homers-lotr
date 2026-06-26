// merit_lvis_2 — Conditional: show list slot 2 only when populated.
int StartingConditional()
{
    return GetLocalInt(GetPCSpeaker(), "merit_lslot_2") > 0;
}
