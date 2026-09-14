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
    MW_MigrateLegacy(oPC);

    // One consumption per character, forever - the flag is keyed on
    // GetObjectUUID(oPC) in mw_db.nss, so a second Mixtape (the Donations
    // Chest restocks one on the test realm) can never grant the +1 again.
    // The spare ring is deliberately NOT destroyed: worn, it is still a
    // +2-to-all-abilities ring, which is the "keep it" branch of this very
    // conversation.
    if (MW_GetFlag(oPC, "mixtape_consumed"))
    {
        FloatingTextStringOnCreature(
            "You have already taken the Mixtape's wisdom into yourself. " +
            "This one can only be worn.", oPC, FALSE);
        return;
    }

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

    MW_SetFlag(oPC, "mixtape_consumed");
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
