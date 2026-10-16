// hw26_charm - Jack-o'-Lantern Charm: Ward the Door (activated), 1 per 90 real
// minutes. For one minute, undead within 10m of the wearer take 4d6 fire a round.

#include "hw_inc"

void HW_WardPulse(object oPC, int nLeft)
{
    if (nLeft <= 0 || !GetIsObjectValid(oPC) || GetIsDead(oPC)) return;
    location l = GetLocation(oPC);
    ApplyEffectAtLocation(DURATION_TYPE_INSTANT, EffectVisualEffect(VFX_IMP_PULSE_FIRE), l);
    object o = GetFirstObjectInShape(SHAPE_SPHERE, 10.0, l, TRUE, OBJECT_TYPE_CREATURE);
    while (GetIsObjectValid(o))
    {
        if (!GetIsDead(o) && GetRacialType(o) == RACIAL_TYPE_UNDEAD && GetIsEnemy(o, oPC))
        {
            ApplyEffectToObject(DURATION_TYPE_INSTANT, EffectDamage(d6(4), DAMAGE_TYPE_FIRE), o);
            ApplyEffectToObject(DURATION_TYPE_INSTANT, EffectVisualEffect(VFX_IMP_FLAME_S), o);
        }
        o = GetNextObjectInShape(SHAPE_SPHERE, 10.0, l, TRUE, OBJECT_TYPE_CREATURE);
    }
    DelayCommand(6.0, HW_WardPulse(oPC, nLeft - 1));
}

void main()
{
    object oPC = OBJECT_SELF;
    if (!GetIsPC(oPC)) return;
    if (!HW_TryUse(oPC, "ward", "Ward the Door", 1)) return;
    AssignCommand(GetModule(), HW_WardPulse(oPC, 10));
}
