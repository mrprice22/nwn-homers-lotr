// Ferny's Return -> Ferny's Ring bridge -- StartingConditional for Bill
// Ferny's grateful greeting. Shown when the character completed the prequel
// (persistent "fret" campaign flag) and has not yet started or finished the
// Ferny's Ring chain this session (its own state is session-local ints).
int StartingConditional()
{
    object oPC = GetPCSpeaker();
    if (!GetCampaignInt("fret", "done", oPC)) return FALSE;
    if (GetLocalInt(oPC, "queststart") != 0) return FALSE;
    if (GetLocalInt(oPC, "thugtest") != 0) return FALSE;
    return TRUE;
}
