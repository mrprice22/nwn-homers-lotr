// merit_ci_dm - Conditional: show "Yes, submit request now!" for an affordable
// DM-fulfilled reward.
int StartingConditional()
{
    object oPC = GetPCSpeaker();
    return GetLocalInt(oPC, "merit_pick_afford")
        && GetLocalInt(oPC, "merit_pick_dm");
}
