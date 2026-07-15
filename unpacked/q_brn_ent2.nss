// Beorn's Garden (roadmap: beorns-garden)
// Carrok / Carrok: Greater OnEnter wrapper: run the areas' previous OnEnter
// (d_cleartrash — which itself chains the anti-kiting leash), then make
// sure the honey hives stand. Same wrapper pattern as q_rid_enter.
void main()
{
    ExecuteScript("d_cleartrash", OBJECT_SELF);

    if (GetIsPC(GetEnteringObject()))
        ExecuteScript("q_brn_spawn", OBJECT_SELF);
}
