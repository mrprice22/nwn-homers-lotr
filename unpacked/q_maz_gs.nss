// The Twentieth Plot of Mazarbul (roadmap: twentieth-plot-mazarbul)
// OnSpawn for Frar the Restless (q_maz_ghost): chain the standard spawn
// script, then give the dwarf his grave-pale ghost-light so the "restless
// shade" reads at a glance (no custom appearance model needed).
void main()
{
    ExecuteScript("x2_def_spawn", OBJECT_SELF);
    ApplyEffectToObject(DURATION_TYPE_PERMANENT,
        SupernaturalEffect(EffectVisualEffect(VFX_DUR_GHOSTLY_VISAGE)),
        OBJECT_SELF);
}
