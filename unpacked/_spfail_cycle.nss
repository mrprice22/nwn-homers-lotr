void main()
{
    object oPC = OBJECT_SELF;
    if (!GetLocalInt(oPC, "SPFAIL_RUNNING")) return;

    if (WillSave(oPC, 45, SAVING_THROW_TYPE_SPELL, OBJECT_INVALID) == 1)
    {
        effect e = GetFirstEffect(oPC);
        while (GetIsEffectValid(e))
        {
            if (GetEffectType(e) == EFFECT_TYPE_SPELL_FAILURE)
                RemoveEffect(oPC, e);
            e = GetNextEffect(oPC);
        }
        FloatingTextStringOnCreature(
            "You resist the magical suppression of the Black Gate.",
            oPC, FALSE);
    }
    else
    {
        ApplyEffectToObject(DURATION_TYPE_PERMANENT,
            EffectSpellFailure(100), oPC);
        FloatingTextStringOnCreature(
            "The dark power of the Black Gate suppresses your arcane ability.",
            oPC, FALSE);
    }

    DelayCommand(60.0f, ExecuteScript("_spfail_cycle", oPC));
}
