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

    // Consuming ALWAYS destroys the ring, whether or not it pays out. One
    // consumption per character, forever - the flag is keyed on
    // GetObjectUUID(oPC) in mw_db.nss, so a second Mixtape (the Donations
    // Chest restocks one on the test realm) can never grant the +1 again.
    // A spare is not left in the player's pack as a wearable +2-to-all ring:
    // that would be a second, quieter reward riding on the test-realm chest,
    // and the chest hands out another copy on demand anyway.
    if (MW_GetFlag(oPC, "mixtape_consumed"))
    {
        DestroyObject(oItem);
        FloatingTextStringOnCreature(
            "You have already taken the Mixtape's wisdom into yourself. " +
            "This one crumbles to dust.", oPC, FALSE);
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
