// Show ammo menu slot 7 only when the scan found at least 8 stacks.
// (Slot gate, mirroring forge_stg_c7.nss.)

int StartingConditional()
{
    return 7 < GetLocalInt(GetPCSpeaker(), "AMMOREP_COUNT");
}
