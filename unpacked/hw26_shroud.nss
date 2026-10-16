// hw26_shroud - Harvest Shroud: Leaf-Fall Step (activated), 3 per 90 real min.
// Improved invisibility and haste for two rounds, in a swirl of dead leaves.

#include "hw_inc"

void main()
{
    object oPC = OBJECT_SELF;
    if (!GetIsPC(oPC)) return;
    if (!HW_TryUse(oPC, "leaf", "Leaf-Fall Step", 3)) return;
    effect e = EffectLinkEffects(EffectInvisibility(INVISIBILITY_TYPE_IMPROVED),
               EffectLinkEffects(EffectHaste(), EffectVisualEffect(VFX_DUR_INVISIBILITY)));
    ApplyEffectToObject(DURATION_TYPE_TEMPORARY, e, oPC, 12.0);
    ApplyEffectToObject(DURATION_TYPE_INSTANT, EffectVisualEffect(VFX_IMP_HASTE), oPC);
}
