// The Riddle Game (roadmap: riddle-game)
// Bree Cave OnEnter wrapper: keep the standard anti-kiting leash, then make
// sure the whispering wretch is home whenever a player walks in. Same
// wrapper pattern as the Meaningwave area-enter scripts (mw_*_enter.nss).
void main()
{
    // Keep creatures in their spawn area (anti-kiting); see leash_to_area.nss.
    ExecuteScript("leash_to_area", OBJECT_SELF);

    if (GetIsPC(GetEnteringObject()))
        ExecuteScript("q_rid_spawn", OBJECT_SELF);
}
