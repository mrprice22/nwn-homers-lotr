//::///////////////////////////////////////////////
//:: shape_merge_inc
//:: Shared equipment-merge helper for all player polymorphs.
//:://////////////////////////////////////////////
/*
    Roadmap item wildshape-shifter-item-merge: merge ALL equipped item
    properties into every druid/shifter/arcane polymorph form, including
    weapon -> claw/bite creature weapons (vanilla only ever merged onto the
    new right-hand item, so animal forms never benefited from a weapon).

    Power balance: merged properties are bounded by the player's own
    forge-capped gear, and duplicate property types on a single item take
    highest-only, so hide-merging yields the best item of each kind rather
    than a stacked sum.

    Used by: nw_s2_wildshape, nw_s2_elemshape, x2_s2_gwildshp,
             nw_s0_polyself, nw_s0_shapechg, nw_s0_tenstrans
*/
//:://////////////////////////////////////////////

#include "x2_inc_itemprop"

// Tunables (compile-time; flip for future balance passes)
const int SHAPE_MERGE_WEAPON = TRUE;  // weapon -> right hand + claws/bite
const int SHAPE_MERGE_ARMOR  = TRUE;  // armor/helm/shield -> hide
const int SHAPE_MERGE_ITEMS  = TRUE;  // rings/amulet/cloak/boots/belt/gloves -> hide

// Snapshot of pre-polymorph equipment, taken before EffectPolymorph is applied.
struct ShapeMergeGear
{
    object oWeapon;
    object oArmor;
    object oHelmet;
    object oShield;
    object oRing1;
    object oRing2;
    object oAmulet;
    object oCloak;
    object oBoots;
    object oBelt;
    object oGloves;
};

// Capture oShifter's equipped items. Call BEFORE applying the polymorph
// effect. Non-shield left-hand items are dropped from the snapshot,
// matching vanilla behavior.
struct ShapeMergeGear ShapeMergeSnapshot(object oShifter);

// Merge the snapshot's item properties onto oShifter's post-polymorph
// creature items. Call AFTER applying the polymorph effect.
void ShapeMergeAll(object oShifter, struct ShapeMergeGear gear);


struct ShapeMergeGear ShapeMergeSnapshot(object oShifter)
{
    struct ShapeMergeGear gear;
    gear.oWeapon = GetItemInSlot(INVENTORY_SLOT_RIGHTHAND, oShifter);
    gear.oArmor  = GetItemInSlot(INVENTORY_SLOT_CHEST, oShifter);
    gear.oHelmet = GetItemInSlot(INVENTORY_SLOT_HEAD, oShifter);
    gear.oShield = GetItemInSlot(INVENTORY_SLOT_LEFTHAND, oShifter);
    gear.oRing1  = GetItemInSlot(INVENTORY_SLOT_LEFTRING, oShifter);
    gear.oRing2  = GetItemInSlot(INVENTORY_SLOT_RIGHTRING, oShifter);
    gear.oAmulet = GetItemInSlot(INVENTORY_SLOT_NECK, oShifter);
    gear.oCloak  = GetItemInSlot(INVENTORY_SLOT_CLOAK, oShifter);
    gear.oBoots  = GetItemInSlot(INVENTORY_SLOT_BOOTS, oShifter);
    gear.oBelt   = GetItemInSlot(INVENTORY_SLOT_BELT, oShifter);
    gear.oGloves = GetItemInSlot(INVENTORY_SLOT_ARMS, oShifter);

    if (GetIsObjectValid(gear.oShield))
    {
        if (GetBaseItemType(gear.oShield) != BASE_ITEM_LARGESHIELD &&
            GetBaseItemType(gear.oShield) != BASE_ITEM_SMALLSHIELD &&
            GetBaseItemType(gear.oShield) != BASE_ITEM_TOWERSHIELD)
        {
            gear.oShield = OBJECT_INVALID;
        }
    }
    return gear;
}

void ShapeMergeAll(object oShifter, struct ShapeMergeGear gear)
{
    object oWeaponNew = GetItemInSlot(INVENTORY_SLOT_RIGHTHAND, oShifter);
    object oHideNew   = GetItemInSlot(INVENTORY_SLOT_CARMOUR, oShifter);

    SetIdentified(oWeaponNew, TRUE);

    int bMergedSomething = FALSE;

    if (SHAPE_MERGE_WEAPON)
    {
        // Unarmed casters: let glove properties ride the natural attacks.
        object oWeaponSrc = gear.oWeapon;
        int bGlovesAsWeapon = FALSE;
        if (!GetIsObjectValid(oWeaponSrc) && GetIsObjectValid(gear.oGloves))
        {
            oWeaponSrc = gear.oGloves;
            bGlovesAsWeapon = TRUE;
        }

        if (GetIsObjectValid(oWeaponSrc))
        {
            // Vanilla path: forms with a manufactured weapon (drow, azer...)
            IPWildShapeCopyItemProperties(oWeaponSrc, oWeaponNew, TRUE);

            // New: natural attacks. Gloves carry no ranged flag, so the
            // helper's ranged-mismatch guard still applies for real weapons.
            object oClaw = GetItemInSlot(INVENTORY_SLOT_CWEAPON_L, oShifter);
            IPWildShapeCopyItemProperties(oWeaponSrc, oClaw, TRUE);
            oClaw = GetItemInSlot(INVENTORY_SLOT_CWEAPON_R, oShifter);
            IPWildShapeCopyItemProperties(oWeaponSrc, oClaw, TRUE);
            oClaw = GetItemInSlot(INVENTORY_SLOT_CWEAPON_B, oShifter);
            IPWildShapeCopyItemProperties(oWeaponSrc, oClaw, TRUE);

            bMergedSomething = TRUE;
        }

        if (bGlovesAsWeapon)
            gear.oGloves = OBJECT_INVALID; // don't also merge them onto the hide
    }

    if (SHAPE_MERGE_ARMOR && GetIsObjectValid(oHideNew))
    {
        IPWildShapeCopyItemProperties(gear.oArmor,  oHideNew);
        IPWildShapeCopyItemProperties(gear.oHelmet, oHideNew);
        IPWildShapeCopyItemProperties(gear.oShield, oHideNew);
        if (GetIsObjectValid(gear.oArmor) || GetIsObjectValid(gear.oHelmet) ||
            GetIsObjectValid(gear.oShield))
            bMergedSomething = TRUE;
    }

    if (SHAPE_MERGE_ITEMS && GetIsObjectValid(oHideNew))
    {
        IPWildShapeCopyItemProperties(gear.oRing1,  oHideNew);
        IPWildShapeCopyItemProperties(gear.oRing2,  oHideNew);
        IPWildShapeCopyItemProperties(gear.oAmulet, oHideNew);
        IPWildShapeCopyItemProperties(gear.oCloak,  oHideNew);
        IPWildShapeCopyItemProperties(gear.oBoots,  oHideNew);
        IPWildShapeCopyItemProperties(gear.oBelt,   oHideNew);
        IPWildShapeCopyItemProperties(gear.oGloves, oHideNew);
        if (GetIsObjectValid(gear.oRing1) || GetIsObjectValid(gear.oRing2) ||
            GetIsObjectValid(gear.oAmulet) || GetIsObjectValid(gear.oCloak) ||
            GetIsObjectValid(gear.oBoots) || GetIsObjectValid(gear.oBelt) ||
            GetIsObjectValid(gear.oGloves))
            bMergedSomething = TRUE;
    }

    if (bMergedSomething && GetIsPC(oShifter))
        FloatingTextStringOnCreature(
            "Your equipment's magic flows into your new form.", oShifter, FALSE);
}
