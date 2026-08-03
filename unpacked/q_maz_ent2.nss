// The Twentieth Plot of Mazarbul (roadmap: twentieth-plot-mazarbul)
// Balin's Tomb OnEnter wrapper: run the area's previous OnEnter
// (mw_bali_enter - which itself chains the anti-kiting leash and the
// Meaningwave Campbell spawn), then make sure the seal-braziers stand.
// Same wrapper pattern as q_brn_ent2 (Beorn's Garden).
void main()
{
    ExecuteScript("mw_bali_enter", OBJECT_SELF);

    if (GetIsPC(GetEnteringObject()))
        ExecuteScript("q_maz_spawn", OBJECT_SELF);
}
