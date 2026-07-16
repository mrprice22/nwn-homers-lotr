// The Banner of the West (roadmap: knight-westernesse-quest)
// Pelennor Fields OnEnter wrapper: keep the area's previous OnEnter
// (d_cleartrash — trash sweep, which itself chains the anti-kiting
// leash), then make sure the banner-stone stands at its waypoint. Same
// wrapper pattern as prsg_enter / q_hrp_ent1.
void main()
{
    // Trash sweep + creature leash (the area's previous OnEnter).
    ExecuteScript("d_cleartrash", OBJECT_SELF);

    if (GetIsPC(GetEnteringObject()))
        ExecuteScript("q_kwn_spawn", OBJECT_SELF);
}
