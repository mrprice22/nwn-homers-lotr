// The Flame of Anor -- Cleric line I (roadmap: cleric-line-early)
// Temple of Illuvatar OnEnter wrapper: chain the existing handler
// (leash_to_area -- keeps creatures pinned to their spawn area), then make sure
// Aldamir keeps his vigil by the Secret Fire. Same wrapper-chaining pattern as
// q_wiz_enter.
void main()
{
    ExecuteScript("leash_to_area", OBJECT_SELF);   // existing templeofilluvata OnEnter

    if (GetIsPC(GetEnteringObject()))
        ExecuteScript("q_clr_spawn", OBJECT_SELF);
}
