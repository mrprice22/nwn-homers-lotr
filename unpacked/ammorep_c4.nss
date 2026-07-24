// Show ammo menu slot 4 only when the scan found at least 5 stacks.
// (Slot gate, mirroring forge_stg_c4.nss.)

int StartingConditional()
{
    return 4 < GetLocalInt(GetPCSpeaker(), "AMMOREP_COUNT");
}
