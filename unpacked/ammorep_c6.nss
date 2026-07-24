// Show ammo menu slot 6 only when the scan found at least 7 stacks.
// (Slot gate, mirroring forge_stg_c6.nss.)

int StartingConditional()
{
    return 6 < GetLocalInt(GetPCSpeaker(), "AMMOREP_COUNT");
}
