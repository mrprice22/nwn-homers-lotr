// The Empty Hand -- Monk line I (roadmap: monk-line-early)
// Emyn Arnen: Peak OnEnter wrapper: chain the existing handler (leash_to_area
// -- keeps creatures pinned to their spawn area), then make sure Orovan the
// Windless is on his summit. Same wrapper-chaining pattern as q_pld_enter.
void main()
{
    ExecuteScript("leash_to_area", OBJECT_SELF);   // existing emynarnen OnEnter

    if (GetIsPC(GetEnteringObject()))
        ExecuteScript("q_mnk_spawn", OBJECT_SELF);
}
