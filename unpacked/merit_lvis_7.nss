// merit_lvis_7 — Conditional: show list slot 7 only when populated.
int StartingConditional()
{
    return GetLocalInt(GetPCSpeaker(), "merit_lslot_7") > 0;
}
