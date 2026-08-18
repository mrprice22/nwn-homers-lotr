// Weather Top / Amon Sul (roadmap: forbidden-realms-key-tier)
// area026 OnEnter wrapper: keep the standard anti-kiting leash, then make sure
// the hill garrison is standing at its posts whenever a player walks in. Same
// wrapper pattern as q_rid_enter.nss and the Meaningwave mw_*_enter.nss scripts.
void main()
{
    // Keep creatures in their spawn area (anti-kiting); see leash_to_area.nss.
    ExecuteScript("leash_to_area", OBJECT_SELF);

    if (GetIsPC(GetEnteringObject()))
        ExecuteScript("wtop_spawn", OBJECT_SELF);
}
