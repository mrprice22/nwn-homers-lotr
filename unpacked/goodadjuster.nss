// goodadjuster - OnUsed on the GOOD light-shaft placeable (Well of Eru,
// Homeless castle, House of Despair) and the GOOD node of factaduster.dlg.
// Takes the Good allegiance: persist it to factiondb (which also applies the
// live reputation against the Goodfaction/Evilfaction anchors - Evil becomes
// hostile on sight) and play the holy VFX.
#include "faction_db"

void main()
{
    object oPC = GetLastUsedBy();
    // An oath to the Enemy (Blackguard's Black Oath) bars the Free Peoples' road.
    if (!Faction_CanSwitchTo(oPC, "Good"))
    {
        FloatingTextStringOnCreature(
            "Your Black Oath binds you - the road of the Free Peoples is closed to you.",
            oPC, FALSE);
        return;
    }
    Faction_SetAllegiance(oPC, "Good");
    ApplyEffectToObject(DURATION_TYPE_INSTANT, EffectVisualEffect(VFX_FNF_LOS_HOLY_30), oPC);
    ApplyEffectToObject(DURATION_TYPE_INSTANT, EffectVisualEffect(VFX_IMP_PULSE_HOLY), oPC);
}
