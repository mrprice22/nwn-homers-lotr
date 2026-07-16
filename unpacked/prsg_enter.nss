// Prestige-order hub (roadmap: prestige-trainer-hub)
// Well of Eru OnEnter wrapper: chain the area's previous OnEnter
// (welloferuenter — starter XP, donations chest, forge scan, and the
// anti-kiting leash), then make sure Halmir the Grey stands at his post.
// Same wrapper pattern as q_maz_ent1 / q_brn_ent1.
void main()
{
    // The area's whole previous OnEnter behavior, unchanged.
    ExecuteScript("welloferuenter", OBJECT_SELF);

    if (GetIsPC(GetEnteringObject()))
        ExecuteScript("prsg_spawn", OBJECT_SELF);
}
