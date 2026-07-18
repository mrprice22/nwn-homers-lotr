// Blood of Elder Days -- Sorcerer line I (roadmap: sorcerer-line-early)
// Ruins of Annuminas OnEnter wrapper: chain the existing handler
// (d_cleartrash -- the area's trash purge), then make sure Erendis of the
// Drowned House is at her fire. Same wrapper-chaining pattern as
// q_bard_enter / q_mnk_enter / q_pld_enter.
void main()
{
    ExecuteScript("d_cleartrash", OBJECT_SELF);   // existing ruinsofannuminas OnEnter

    if (GetIsPC(GetEnteringObject()))
        ExecuteScript("q_sor_spawn", OBJECT_SELF);
}
