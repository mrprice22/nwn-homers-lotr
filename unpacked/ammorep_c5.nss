// Show ammo menu slot 5 only when the scan found at least 6 stacks.
// (Slot gate, mirroring forge_stg_c5.nss.)

int StartingConditional()
{
    return 5 < GetLocalInt(GetPCSpeaker(), "AMMOREP_COUNT");
}
