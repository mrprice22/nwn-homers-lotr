// The Cipher in the Inn (roadmap: harper-scout-quest)
// Prancing Pony ground floor OnEnter wrapper: keep the standard
// anti-kiting leash (the area's previous OnEnter), then make sure the
// Harper contact keeps her corner table. Same wrapper pattern as
// prsg_enter / q_brn_ent1.
void main()
{
    // Keep creatures in their spawn area (anti-kiting); see leash_to_area.nss.
    ExecuteScript("leash_to_area", OBJECT_SELF);

    if (GetIsPC(GetEnteringObject()))
        ExecuteScript("q_hrp_spawn", OBJECT_SELF);
}
