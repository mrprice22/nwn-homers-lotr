// hw26_grin - Jack's Grin: Hollow Laughter (activated), 3 uses per 90 real min.
//
// Enemies within 15m make a Will save against death (DC 30) or die. Those who
// pass - and every boss-class creature (CR > 60), which is never slain outright
// - are frightened for 2 rounds and take 6d12 magical damage. Allies untouched.

#include "hw_inc"

void main()
{
    object oPC = OBJECT_SELF;
    if (!GetIsPC(oPC)) return;
    if (!HW_TryUse(oPC, "laugh", "Hollow Laughter", 3)) return;

    location lMe = GetLocation(oPC);
    PlaySound("as_pl_lafspook" + IntToString(1 + Random(3)));
    ApplyEffectAtLocation(DURATION_TYPE_INSTANT, EffectVisualEffect(VFX_FNF_WAIL_O_BANSHEES), lMe);
    object o = GetFirstObjectInShape(SHAPE_SPHERE, 15.0, lMe, TRUE, OBJECT_TYPE_CREATURE);
    while (GetIsObjectValid(o))
    {
        if (!GetIsDead(o) && GetIsEnemy(o, oPC))
        {
            int bBoss = GetChallengeRating(o) > 60.0 || GetPlotFlag(o) || GetImmortal(o);
            if (!bBoss && !WillSave(o, 30, SAVING_THROW_TYPE_DEATH, oPC))
            {
                ApplyEffectToObject(DURATION_TYPE_INSTANT, EffectVisualEffect(VFX_IMP_DEATH), o);
                ApplyEffectToObject(DURATION_TYPE_INSTANT, EffectDeath(), o);
            }
            else
            {
                ApplyEffectToObject(DURATION_TYPE_INSTANT, EffectDamage(d12(6), DAMAGE_TYPE_MAGICAL), o);
                ApplyEffectToObject(DURATION_TYPE_TEMPORARY, EffectFrightened(), o, 12.0);
            }
        }
        o = GetNextObjectInShape(SHAPE_SPHERE, 15.0, lMe, TRUE, OBJECT_TYPE_CREATURE);
    }
}
