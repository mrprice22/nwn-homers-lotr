// The Unbroken Shield -- Fighter line I (roadmap: fighter-line-early)
// Prancing Pony ground-floor OnEnter wrapper: chain the existing wrapper
// (q_hrp_ent1 -- which itself keeps the anti-kiting leash and spawns the Harper
// contact), then make sure Hallas the Shieldwarden keeps his corner. Same
// wrapper-chaining pattern as q_hrp_ent1 / prsg_enter / q_hob_enter.
void main()
{
    ExecuteScript("q_hrp_ent1", OBJECT_SELF);   // leash + Harper contact

    if (GetIsPC(GetEnteringObject()))
        ExecuteScript("q_ftr_spawn", OBJECT_SELF);
}
