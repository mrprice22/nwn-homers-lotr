void main()
{
    int iRand = Random(8) + 1;
    object oMoveTo = GetWaypointByTag("WP_LegolasGreenleaf_0" + IntToString(iRand));
    object oVictim = GetLastPerceived();
    location lStart = GetLocation(OBJECT_SELF);

    effect eVis   = EffectVisualEffect(18);
    effect eVis1  = EffectVisualEffect(29);
    effect eVis2  = EffectVisualEffect(74);
    effect eSmoke = EffectVisualEffect(VFX_FNF_SMOKE_PUFF);
    effect eDamage = EffectDamage(d100(2), DAMAGE_TYPE_SONIC, DAMAGE_POWER_PLUS_FIVE);

    // Smoke puff at departure - intentional vanish, not a glitch
    DelayCommand(0.0f, ApplyEffectAtLocation(DURATION_TYPE_INSTANT, eSmoke, lStart));
    DelayCommand(0.0f, ApplyEffectToObject(DURATION_TYPE_TEMPORARY, eVis,  OBJECT_SELF, 6.0));
    DelayCommand(0.5f, ApplyEffectToObject(DURATION_TYPE_TEMPORARY, eVis1, OBJECT_SELF, 6.0));
    DelayCommand(1.0f, ApplyEffectToObject(DURATION_TYPE_TEMPORARY, eVis2, OBJECT_SELF, 6.0));

    if (GetIsObjectValid(oMoveTo))
    {
        DelayCommand(1.5f, ApplyEffectAtLocation(DURATION_TYPE_INSTANT, eSmoke, GetLocation(oMoveTo)));
        DelayCommand(1.5f, ApplyEffectToObject(DURATION_TYPE_TEMPORARY, eVis,  oMoveTo, 6.0));
        DelayCommand(2.2f, ApplyEffectToObject(DURATION_TYPE_TEMPORARY, eVis1, oMoveTo, 6.0));
        DelayCommand(2.5f, ApplyEffectToObject(DURATION_TYPE_TEMPORARY, eVis2, oMoveTo, 6.0));
        ActionJumpToObject(oMoveTo, TRUE);
    }

    if (GetIsObjectValid(oVictim) && GetIsPC(oVictim) &&
        GetArea(oVictim) == GetArea(OBJECT_SELF) &&
        GetIsEnemy(oVictim, OBJECT_SELF))
    {
        DelayCommand(3.0f, ApplyEffectToObject(DURATION_TYPE_INSTANT, eDamage, oVictim));
        ActionAttack(oVictim, FALSE);
    }

    DelayCommand(5.6f, ClearAllActions());
}
