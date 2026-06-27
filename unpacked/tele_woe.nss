// tele_woe — Rest-menu "To. The Well of Eru." teleport. Before sending the PC to
// the Well of Eru, it records their current spot as slot 0 and arms the return
// (merit unlock 102), so the "Return to last Well-of-Eru point" option brings
// them back here exactly once.
//
// This is the ONLY path that arms the return: death/respawn does not touch
// tele_state, so dying never counts as a Well-of-Eru teleport. The jump below is
// a faithful copy of _teleportpvp (the prior reply script) so the destination is
// unchanged.
#include "tele_db"
void main()
{
    object oPC = GetPCSpeaker();

    // Remember where they were and arm a single return.
    Tele_SaveSlot(oPC, 0);
    Tele_SetArmed(oPC, TRUE);

    // --- original _teleportpvp behaviour ---
    object oTarget = GetWaypointByTag("pvp");
    location lTarget = GetLocation(oTarget);

    AssignCommand(oPC, ClearAllActions());
    AssignCommand(oPC, ActionJumpToLocation(lTarget));

    effect eAppear1 = EffectDisappear(VFX_FNF_LOS_EVIL_30);
    effect eVis1 = EffectVisualEffect(VFX_FNF_SUMMON_EPIC_UNDEAD);
    effect eVis2 = EffectVisualEffect(VFX_FNF_LOS_NORMAL_30);
    ApplyEffectToObject(DURATION_TYPE_PERMANENT, eVis1, oPC);
    ApplyEffectToObject(DURATION_TYPE_PERMANENT, eVis2, oPC);
    ApplyEffectToObject(DURATION_TYPE_PERMANENT, eAppear1, oPC, 3.0);
    DelayCommand(1.0, AssignCommand(oPC, ActionJumpToObject(GetWaypointByTag("secondchance"))));
}
