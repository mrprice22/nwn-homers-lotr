// The Thirteenth Ent (roadmap: thirteenth-ent)
// Fangorn Forest (fangornforest) OnEnter wrapper: keep the standard
// anti-kiting leash, then make sure Leaflock is standing where he stood.
// Same wrapper pattern as q_hob_enter (Hobbiton) and q_brn_ent1 (Beorn).
void main()
{
    ExecuteScript("leash_to_area", OBJECT_SELF);

    if (GetIsPC(GetEnteringObject()))
        ExecuteScript("q_ent_spawn", OBJECT_SELF);
}
