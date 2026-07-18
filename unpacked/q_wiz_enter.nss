// The Colour of Power -- Wizard line I (roadmap: wizard-line-early)
// Bag End OnEnter wrapper: chain the existing handler (leash_to_area -- keeps
// creatures pinned to their spawn area), then make sure Findegil the Grey keeps
// his study by the hearth. Same wrapper-chaining pattern as q_rog_enter.
void main()
{
    ExecuteScript("leash_to_area", OBJECT_SELF);   // existing bagend001 OnEnter

    if (GetIsPC(GetEnteringObject()))
        ExecuteScript("q_wiz_spawn", OBJECT_SELF);
}
