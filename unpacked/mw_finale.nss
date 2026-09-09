//::///////////////////////////////////////////////
//:: mw_finale -- Akira reply action: grant the Mixtape and close the meta-quest.
//:://////////////////////////////////////////////
#include "mw_unlock_inc"

void main()
{
    object oPC = GetPCSpeaker();
    if (MW_UnlockCount(oPC) < MW_ROSTER_SIZE) return;
    if (MW_GetFlag(oPC, "finale")) return;

    MW_SetFlag(oPC, "finale");
    CreateItemOnObject("mw_mixtape", oPC, 1);
    AddJournalQuestEntry(MW_META_QUEST, MW_ROSTER_SIZE + 2, oPC, TRUE, FALSE);

    ApplyEffectToObject(DURATION_TYPE_INSTANT,
        EffectVisualEffect(VFX_FNF_PWKILL), oPC);
    FloatingTextStringOnCreature(
        "Akira passes you the mixtape. The path of meaning is walked.",
        oPC, FALSE);
    GiveXPToCreature(oPC, 50000);
}
