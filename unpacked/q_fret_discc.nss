// Ferny's Return -> Ferny's Ring bridge -- StartingConditional for Bill
// Ferny's grateful greeting. Shown when the character completed the prequel
// (persistent "fret" campaign flag) and has not yet started or finished the
// Ferny's Ring chain (its state is persisted in the same "fret" campaign DB:
// ring_qstart / ring_stage).
int StartingConditional()
{
    object oPC = GetPCSpeaker();
    if (!GetCampaignInt("fret", "done", oPC)) return FALSE;
    // Ring-chain state is now persistent (campaign DB "fret") -- was the
    // non-persistent LocalInts "queststart"/"thugtest", which reset every
    // relog and re-opened this greeting after each reboot.
    if (GetCampaignInt("fret", "ring_qstart", oPC) != 0) return FALSE;
    if (GetCampaignInt("fret", "ring_stage", oPC) != 0) return FALSE;
    return TRUE;
}
