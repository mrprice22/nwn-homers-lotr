// Fires when the player confirms consuming Akira's Mixtape.
// Destroys the ring and permanently adds +1 to all six ability scores.
#include "mw_unlock_inc"
#include "hgll_leto_inc"

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

    HGLL_AddStatPoint(oPC, ABILITY_STRENGTH);
    HGLL_AddStatPoint(oPC, ABILITY_DEXTERITY);
    HGLL_AddStatPoint(oPC, ABILITY_CONSTITUTION);
    HGLL_AddStatPoint(oPC, ABILITY_INTELLIGENCE);
    HGLL_AddStatPoint(oPC, ABILITY_WISDOM);
    HGLL_AddStatPoint(oPC, ABILITY_CHARISMA);
    HGLL_FlushChanges(oPC);

    ApplyEffectToObject(DURATION_TYPE_INSTANT,
        EffectVisualEffect(VFX_FNF_PWKILL), oPC);
    FloatingTextStringOnCreature(
        "The Mixtape dissolves into light. Its wisdom is now yours forever.",
        oPC, FALSE);
}
