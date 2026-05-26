//::///////////////////////////////////////////////
//:: mw_wayshrn_us -- Wayshrine OnUsed: teleport unlocked PCs into the Hall.
//::
//:: Players who have not yet unlocked a single guide get a gentle message
//:: and are not teleported. Players who arrive while the Hall is occupied
//:: by another seeker are also turned away.
//:://////////////////////////////////////////////
#include "mw_unlock_inc"

void main()
{
    object oPC = GetLastUsedBy();
    if (!GetIsPC(oPC)) return;

    MW_IntroJournal(oPC);

    if (MW_UnlockCount(oPC) < 1)
    {
        FloatingTextStringOnCreature(
            "The obelisk hums, but the music is too distant. Find a legend first.",
            oPC, FALSE);
        return;
    }

    object oWP = GetWaypointByTag("wp_mw_hall_in");
    if (!GetIsObjectValid(oWP))
    {
        FloatingTextStringOnCreature(
            "The Hall is unreachable. (wp_mw_hall_in missing.)",
            oPC, FALSE);
        return;
    }

    if (GetLocalInt(GetModule(), "MW_HALL_OCCUPIED"))
    {
        FloatingTextStringOnCreature(
            "The Hall of Legends is occupied. Return when the seeker within has departed.",
            oPC, FALSE);
        return;
    }

    SetLocalInt(GetModule(), "MW_HALL_OCCUPIED", 1);
    ApplyEffectToObject(DURATION_TYPE_INSTANT,
        EffectVisualEffect(VFX_IMP_UNSUMMON), oPC);
    AssignCommand(oPC, ClearAllActions());
    AssignCommand(oPC, ActionJumpToLocation(GetLocation(oWP)));
}
