// Tales That Live Forever -- Bard line I (roadmap: bard-line-early)
// Rivendell Upper Halls OnEnter wrapper: chain the existing handler
// (mw_riv_enter -- leash_to_area, trash purge and the Meaningwave spawn), then
// make sure Lindir of the Hall of Fire is by the fire. Same wrapper-chaining
// pattern as q_mnk_enter / q_pld_enter.
void main()
{
    ExecuteScript("mw_riv_enter", OBJECT_SELF);   // existing rivendellupperha OnEnter

    if (GetIsPC(GetEnteringObject()))
        ExecuteScript("q_bard_spawn", OBJECT_SELF);
}
