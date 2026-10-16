// hw_dread_en - Crown aura (Dread of the Harvest), OnEnter AND OnHeartbeat.
//
// Every enemy of the wearer inside the 10m aura takes -4 attack, -4 saves and
// -4 AC. Applied for 7 seconds and renewed every heartbeat, so it falls off on
// its own a moment after a creature leaves or the Crown comes off - no exit
// bookkeeping to get wrong.

void HW_Dread(object oTarget, object oWearer)
{
    if (!GetIsObjectValid(oTarget) || GetIsDead(oTarget)) return;
    if (GetObjectType(oTarget) != OBJECT_TYPE_CREATURE) return;
    if (!GetIsEnemy(oTarget, oWearer)) return;
    effect e = GetFirstEffect(oTarget);
    while (GetIsEffectValid(e))
    {
        if (GetEffectTag(e) == "hw_dread") RemoveEffect(oTarget, e);
        e = GetNextEffect(oTarget);
    }
    effect eD = EffectLinkEffects(EffectAttackDecrease(4),
                EffectLinkEffects(EffectSavingThrowDecrease(SAVING_THROW_ALL, 4),
                                  EffectACDecrease(4)));
    ApplyEffectToObject(DURATION_TYPE_TEMPORARY,
        TagEffect(SupernaturalEffect(eD), "hw_dread"), oTarget, 7.0);
}

void main()
{
    object oWearer = GetAreaOfEffectCreator();
    object oIn = GetEnteringObject();
    if (GetIsObjectValid(oIn))
    {
        HW_Dread(oIn, oWearer);
        return;
    }
    // Heartbeat: everyone currently inside.
    object o = GetFirstInPersistentObject(OBJECT_SELF, OBJECT_TYPE_CREATURE);
    while (GetIsObjectValid(o))
    {
        HW_Dread(o, oWearer);
        o = GetNextInPersistentObject(OBJECT_SELF, OBJECT_TYPE_CREATURE);
    }
}
