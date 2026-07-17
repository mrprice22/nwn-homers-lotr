// Concerning Hobbits (roadmap: concerning-hobbits)
// Hobbiton OnEnter wrapper: keep the standard anti-kiting leash, then make
// sure Odo Proudfoot is at his scroll whenever a player walks in. Same
// wrapper pattern as q_rid_enter (Bree Cave) and the Meaningwave enters.
void main()
{
    ExecuteScript("leash_to_area", OBJECT_SELF);

    if (GetIsPC(GetEnteringObject()))
        ExecuteScript("q_hob_spawn", OBJECT_SELF);
}
