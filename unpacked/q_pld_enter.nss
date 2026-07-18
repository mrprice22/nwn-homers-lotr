// Oathsworn to the West -- Paladin line I (roadmap: paladin-line-early)
// Minas Tirith: Keep OnEnter wrapper: chain the existing handler (leash_to_area
// -- keeps creatures pinned to their spawn area), then make sure Hallas the
// Oathkeeper is at his post. Same wrapper-chaining pattern as q_drd_enter.
void main()
{
    ExecuteScript("leash_to_area", OBJECT_SELF);   // existing area005 OnEnter

    if (GetIsPC(GetEnteringObject()))
        ExecuteScript("q_pld_spawn", OBJECT_SELF);
}
