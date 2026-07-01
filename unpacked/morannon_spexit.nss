void main()
{
    object oExiting = GetExitingObject();
    DeleteLocalInt(oExiting, "SPFAIL_RUNNING");
    effect e = GetFirstEffect(oExiting);
    while (GetIsEffectValid(e))
    {
        if (GetEffectType(e) == EFFECT_TYPE_SPELL_FAILURE &&
            GetEffectDurationType(e) == DURATION_TYPE_PERMANENT)
            RemoveEffect(oExiting, e);
        e = GetNextEffect(oExiting);
    }
}
