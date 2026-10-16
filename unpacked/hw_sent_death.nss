// hw_sent_death - the Scarecrow Sentinel falls: its straw bursts into a
// harvest blessing that heals its master's party within 10m by 200.

void main()
{
    object oS = OBJECT_SELF;
    object oMaster = GetMaster(oS);
    location l = GetLocation(oS);
    ApplyEffectAtLocation(DURATION_TYPE_INSTANT, EffectVisualEffect(VFX_FNF_LOS_HOLY_30), l);
    object o = GetFirstObjectInShape(SHAPE_SPHERE, 10.0, l, FALSE, OBJECT_TYPE_CREATURE);
    while (GetIsObjectValid(o))
    {
        if (!GetIsDead(o) && GetIsObjectValid(oMaster) && GetIsFriend(o, oMaster))
        {
            ApplyEffectToObject(DURATION_TYPE_INSTANT, EffectHeal(200), o);
            ApplyEffectToObject(DURATION_TYPE_INSTANT, EffectVisualEffect(VFX_IMP_HEALING_L), o);
        }
        o = GetNextObjectInShape(SHAPE_SPHERE, 10.0, l, FALSE, OBJECT_TYPE_CREATURE);
    }
    ExecuteScript("nw_ch_ac7", oS);
}
