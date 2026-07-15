// Beorn's Garden (roadmap: beorns-garden)
// Beorn homestead OnEnter wrapper: keep the standard anti-kiting leash
// (the area's previous OnEnter), then make sure the honey hives stand.
// Same wrapper pattern as q_rid_enter (the Riddle Game).
void main()
{
    // Keep creatures in their spawn area (anti-kiting); see leash_to_area.nss.
    ExecuteScript("leash_to_area", OBJECT_SELF);

    if (GetIsPC(GetEnteringObject()))
        ExecuteScript("q_brn_spawn", OBJECT_SELF);
}
