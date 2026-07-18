// The Long Shadow -- Rogue line I (roadmap: rogue-line-early)
// Prancing Pony ground-floor OnEnter wrapper: chain the existing wrapper
// (q_ftr_enter -- which itself chains q_hrp_ent1's leash + Harper contact and
// then spawns Hallas the Shieldwarden), then make sure Fenn the Shade keeps his
// watch by the doorway. Same wrapper-chaining pattern as q_ftr_enter.
void main()
{
    ExecuteScript("q_ftr_enter", OBJECT_SELF);  // leash + Harper + Hallas spawn

    if (GetIsPC(GetEnteringObject()))
        ExecuteScript("q_rog_spawn", OBJECT_SELF);
}
