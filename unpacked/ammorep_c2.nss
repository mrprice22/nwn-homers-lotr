// Show ammo menu slot 2 only when the scan found at least 3 stacks.
// (Slot gate, mirroring forge_stg_c2.nss.)

int StartingConditional()
{
    return 2 < GetLocalInt(GetPCSpeaker(), "AMMOREP_COUNT");
}
