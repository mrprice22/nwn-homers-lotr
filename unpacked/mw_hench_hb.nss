//::///////////////////////////////////////////////
//:: mw_hench_hb -- shared heartbeat for MeaningWave guide henchmen.
//:: Delegates to nw_ch_ac1 for standard associate AI, then adds
//:: master-follow / despawn-on-master-lost (same model as hench_demon_hb).
//:://////////////////////////////////////////////
void main()
{
    ExecuteScript("nw_ch_ac1", OBJECT_SELF);

    object oMaster = GetMaster();
    if (!GetIsObjectValid(oMaster))
    {
        ApplyEffectToObject(DURATION_TYPE_INSTANT, EffectDisappear(), OBJECT_SELF);
        return;
    }
    if (GetArea(OBJECT_SELF) != GetArea(oMaster))
    {
        location lTarget = GetLocation(oMaster);
        AssignCommand(OBJECT_SELF, ClearAllActions());
        DelayCommand(0.1, AssignCommand(OBJECT_SELF, ActionJumpToLocation(lTarget)));
    }
}
