// merit_ci_instant — Conditional: show "Yes, grant it now!" for an affordable,
// instant, non-tournament reward.
int StartingConditional()
{
    object oPC = GetPCSpeaker();
    return GetLocalInt(oPC, "merit_pick_afford")
        && !GetLocalInt(oPC, "merit_pick_dm")
        && GetLocalInt(oPC, "merit_pick_id") != 302;
}
