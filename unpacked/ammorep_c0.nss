// Show ammo menu slot 0 only when the scan found at least 1 stacks.
// (Slot gate, mirroring forge_stg_c0.nss.)

int StartingConditional()
{
    return 0 < GetLocalInt(GetPCSpeaker(), "AMMOREP_COUNT");
}
