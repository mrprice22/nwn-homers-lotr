// merit_tvis_6 - Conditional: show tournament picker slot 6 (only while
// choosing tournament gear and the slot is populated and affordable).
int StartingConditional()
{
    object oPC = GetPCSpeaker();
    return GetLocalInt(oPC, "merit_pick_id") == 302
        && GetLocalInt(oPC, "merit_pick_afford")
        && GetLocalString(oPC, "merit_tslot_6") != "";
}
