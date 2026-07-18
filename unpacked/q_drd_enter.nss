// The Breathing of the World -- Druid line I (roadmap: druid-line-early)
// Rhosgobel OnEnter wrapper: chain the existing handler (leash_to_area -- keeps
// creatures pinned to their spawn area), then make sure Naldor the Green is
// keeping the wood. Same wrapper-chaining pattern as q_rng_enter.
void main()
{
    ExecuteScript("leash_to_area", OBJECT_SELF);   // existing rhosgobel OnEnter

    if (GetIsPC(GetEnteringObject()))
        ExecuteScript("q_drd_spawn", OBJECT_SELF);
}
