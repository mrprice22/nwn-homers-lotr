// hw26_crown - The Pumpkin King's Crown: Harvest Moon (activated).
//
// 1 use per 90 real minutes (resting does not refresh it - see HW_TryUse).
// A 20m burst of unholy moonfire on every enemy; each one it kills leaves a
// Harvest Ward, a jack-o'-lantern that heals the wearer's allies for 30s.
// The Crown's always-on aura (Dread of the Harvest) is hw_dread_en/hb, applied
// by HW_RefreshPrizeFx while the Crown is worn.

#include "hw_inc"

void HW_MoonCheck(object oVictim, object oPC, location l)
{
    if (!GetIsObjectValid(oVictim) || GetIsDead(oVictim))
        HW_HealingPumpkin(oPC, l);
}

void main()
{
    object oPC = OBJECT_SELF;
    if (!GetIsPC(oPC)) return;
    if (!HW_TryUse(oPC, "moon", "Harvest Moon", 1)) return;

    location lMe = GetLocation(oPC);
    ApplyEffectAtLocation(DURATION_TYPE_INSTANT, EffectVisualEffect(VFX_FNF_LOS_EVIL_30), lMe);
    int nWards = 0;
    object o = GetFirstObjectInShape(SHAPE_SPHERE, 20.0, lMe, TRUE, OBJECT_TYPE_CREATURE);
    while (GetIsObjectValid(o))
    {
        if (!GetIsDead(o) && GetIsEnemy(o, oPC))
        {
            int nDmg = d12(10) + GetHitDice(oPC);
            ApplyEffectToObject(DURATION_TYPE_INSTANT, EffectDamage(nDmg, DAMAGE_TYPE_MAGICAL), o);
            ApplyEffectToObject(DURATION_TYPE_INSTANT, EffectVisualEffect(VFX_IMP_DEATH), o);
            if (nWards < 6)
            {
                nWards++;
                DelayCommand(0.5, HW_MoonCheck(o, oPC, GetLocation(o)));
            }
        }
        o = GetNextObjectInShape(SHAPE_SPHERE, 20.0, lMe, TRUE, OBJECT_TYPE_CREATURE);
    }
}
