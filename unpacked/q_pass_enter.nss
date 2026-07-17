// Pass the Pass (roadmap: pass-the-pass)
// Area OnEnter wrapper for foothillsofthemi and mistymountainsb: preserve the
// original OnEnter (d_cleartrash), then make sure the quest NPCs are at their
// waypoints whenever a player walks in. Same wrapper pattern as q_hob_enter.
void main()
{
    ExecuteScript("d_cleartrash", OBJECT_SELF);

    if (GetIsPC(GetEnteringObject()))
        ExecuteScript("q_pass_spawn", OBJECT_SELF);
}
