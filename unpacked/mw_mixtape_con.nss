// Fires when the player confirms consuming Akira's Mixtape.
// Destroys the ring and permanently adds +1 to all six ability scores.
#include "mw_unlock_inc"
#include "nwnx_creature"

// Permanently raises one ability score by 1 on the PC's base (raw) stats.
// Formerly HGLL_AddStatPoint() from the retired legendary leveler
// (roadmap: ll-hgll-remove-scripts); inlined here so the mixtape no longer
// depends on any hgll_* include.
void MixtapeRaiseStat(object oPC, int nStat)
{
    int nCur = NWNX_Creature_GetRawAbilityScore(oPC, nStat);
    NWNX_Creature_SetRawAbilityScore(oPC, nStat, nCur + 1);
}

void main()
{
    object oPC = GetPCSpeaker();

    if (GetCampaignInt(MW_DB, "mixtape_consumed", oPC)) return;

    // Anti-exploit: verify item is still in inventory before committing anything.
    // Dropping the ring mid-conversation then clicking Consume would otherwise
    // grant stats without consuming the item.
    object oItem = GetItemPossessedBy(oPC, "mw_mixtape");
    if (!GetIsObjectValid(oItem))
    {
        FloatingTextStringOnCreature(
            "The Mixtape must be in your possession to be consumed.", oPC, FALSE);
        return;
    }

    SetCampaignInt(MW_DB, "mixtape_consumed", 1, oPC);
    DestroyObject(oItem);

    MixtapeRaiseStat(oPC, ABILITY_STRENGTH);
    MixtapeRaiseStat(oPC, ABILITY_DEXTERITY);
    MixtapeRaiseStat(oPC, ABILITY_CONSTITUTION);
    MixtapeRaiseStat(oPC, ABILITY_INTELLIGENCE);
    MixtapeRaiseStat(oPC, ABILITY_WISDOM);
    MixtapeRaiseStat(oPC, ABILITY_CHARISMA);
    // Write the raised base stats through to the .bic immediately.
    ExportSingleCharacter(oPC);

    ApplyEffectToObject(DURATION_TYPE_INSTANT,
        EffectVisualEffect(VFX_FNF_PWKILL), oPC);
    FloatingTextStringOnCreature(
        "The Mixtape dissolves into light. Its wisdom is now yours forever.",
        oPC, FALSE);
}
