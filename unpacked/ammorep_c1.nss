// Show ammo menu slot 1 only when the scan found at least 2 stacks.
// (Slot gate, mirroring forge_stg_c1.nss.)

int StartingConditional()
{
    return 1 < GetLocalInt(GetPCSpeaker(), "AMMOREP_COUNT");
}
