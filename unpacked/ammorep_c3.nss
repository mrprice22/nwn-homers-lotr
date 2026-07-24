// Show ammo menu slot 3 only when the scan found at least 4 stacks.
// (Slot gate, mirroring forge_stg_c3.nss.)

int StartingConditional()
{
    return 3 < GetLocalInt(GetPCSpeaker(), "AMMOREP_COUNT");
}
