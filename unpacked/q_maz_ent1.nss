// The Twentieth Plot of Mazarbul (roadmap: twentieth-plot-mazarbul)
// Chamber of Records Wlkwy OnEnter wrapper: keep the standard anti-kiting
// leash (the area's previous OnEnter), then make sure Frar's shade and the
// seal-braziers stand. Same wrapper pattern as q_brn_ent1 (Beorn's Garden).
void main()
{
    // Keep creatures in their spawn area (anti-kiting); see leash_to_area.nss.
    ExecuteScript("leash_to_area", OBJECT_SELF);

    if (GetIsPC(GetEnteringObject()))
        ExecuteScript("q_maz_spawn", OBJECT_SELF);
}
