// The Uncrowned Path -- Ranger line I (roadmap: ranger-line-early)
// Ranger waystation OnEnter wrapper: chain the existing handler (leash_to_area
// -- keeps creatures pinned to their spawn area), then make sure Halbarad keeps
// his vigil at the waystation. Same wrapper-chaining pattern as q_clr_enter.
void main()
{
    ExecuteScript("leash_to_area", OBJECT_SELF);   // existing rangerwaystation OnEnter

    if (GetIsPC(GetEnteringObject()))
        ExecuteScript("q_rng_spawn", OBJECT_SELF);
}
