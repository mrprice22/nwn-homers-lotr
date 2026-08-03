//::///////////////////////////////////////////////
//:: Demon henchman heartbeat - persistent-follow wrapper around the
//:: standard nw_ch_ac1 (HotU associate heartbeat). Adds two behaviors
//:: on top of stock henchman AI:
//::   1. If the master is gone, the demon vanishes.
//::   2. If the master is in a different area, jump to follow.
//:://////////////////////////////////////////////
//::
//:: Was previously a copy-paste of X0_INC_HENAI's logic plus the two
//:: extra behaviors above; that script no longer compiled because the
//:: engine-base x0_inc_henai pulls in identifiers (GetIsFollower,
//:: FireHenchman, the CLEAR_X0_INC_HENAI_* constants, etc.) that
//:: nwn_script_comp does not see in the resman. Delegating to
//:: nw_ch_ac1 via ExecuteScript keeps the runtime behavior intact
//:: while letting this file compile cleanly.
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
