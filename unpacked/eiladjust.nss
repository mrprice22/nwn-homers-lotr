// eiladjust — OnUsed on the EVIL light-shaft placeable (Well of Eru, Homeless
// castle, House of Despair; blueprint solred.utp) and the EVIL node of
// factaduster.dlg. Takes the Evil allegiance: persist it to factiondb (which
// also applies the live reputation against the Goodfaction/Evilfaction anchors
// — Good becomes hostile on sight) and play the evil VFX.
#include "faction_db"

void main()
{
    object oPC = GetLastUsedBy();
    // An oath to the West (Paladin's Oath) forbids taking the dark road.
    if (!Faction_CanSwitchTo(oPC, "Evil"))
    {
        FloatingTextStringOnCreature(
            "Your oath to the West forbids this — the dark road is closed to you.",
            oPC, FALSE);
        return;
    }
    Faction_SetAllegiance(oPC, "Evil");
    ApplyEffectToObject(DURATION_TYPE_INSTANT, EffectVisualEffect(VFX_FNF_LOS_EVIL_20), oPC);
    ApplyEffectToObject(DURATION_TYPE_INSTANT, EffectVisualEffect(VFX_IMP_HEAD_EVIL), oPC);
}
