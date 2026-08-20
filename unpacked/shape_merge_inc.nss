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

    Roadmap item shifter-stats-defect adds the other half. Merging properties
    was not enough, for two reasons:

      1. EffectPolymorph SETS base STR/CON/DEX from polymorph.2da (wolf
         13/15/15, ancient dragon 48/32/36). This server runs to level 60 with
         max-ability-bonus 24, so every form's numbers sit at or below a real
         character's own base scores and shifting was a DOWNGRADE. It also
         does not repay the BASE armour class of the armour and shield that
         stop applying - only their properties merge, never plate's own 8 AC.
      2. Creature weapons ignore ITEM_PROPERTY_ENHANCEMENT_BONUS for attack
         and damage rolls (it only buys damage-reduction bypass), so a +9
         weapon merged onto a claw paid out nothing. Players saw exactly this:
         "they are [passed through] for the shapes with weapons, the rest only
         get the damage".

    The rule ShapeMergeStatFloor implements: a geared character gets the same
    shape bonus a naked one would get under stock rules, on top of their own
    stats, measured from a stock-rules caster baseline of SHAPE_BASE_ANCHOR.

        form_bonus  = max(0, polymorph.2da value - SHAPE_BASE_ANCHOR)
        base target = own base + form_bonus       (never below own base)
        AC target   = unshifted AC + form NATURALACBONUS

    So brown bear (27/19/13) is +15/+7/+1 on top of what you already have,
    ancient dragon (48/32/36) is +36/+20/+24, and a badger (STR 8) is +0 -
    weak forms stay weak, strong forms are worth shifting into.

    Used by: nw_s2_wildshape, nw_s2_elemshape, x2_s2_gwildshp,
             nw_s0_polyself, nw_s0_shapechg, nw_s0_tenstrans
*/
//:://////////////////////////////////////////////

#include "x2_inc_itemprop"

// Tunables (compile-time; flip for future balance passes)
const int SHAPE_MERGE_WEAPON = TRUE;  // weapon -> right hand + claws/bite
const int SHAPE_MERGE_ARMOR  = TRUE;  // armor/helm/shield -> hide
const int SHAPE_MERGE_ITEMS  = TRUE;  // rings/amulet/cloak/boots/belt/gloves -> hide
const int SHAPE_MERGE_STATS  = TRUE;  // own base + the form's vanilla bonus

// Translate a merged weapon's enhancement bonus into attack + physical damage
// on creature weapons, which the engine otherwise ignores for both. Flip to
// FALSE if UAT ever shows a +9 weapon giving +18 on claws (that would mean the
// engine started honouring enhancement there, and this would double-count).
const int SHAPE_MERGE_ENH_AS_ATTACK = TRUE;

// The stock-rules score each form's bonus is measured from: a vanilla caster's
// 12 in the physical abilities. One knob retunes the whole system.
const int SHAPE_BASE_ANCHOR = 12;

// Per-ability ceiling on the top-up, purely defensive against a garbage 2DA
// read. Nothing legitimate comes close: the largest real gap is a level-60
// character in a wolf (base ~45 vs the form's 13).
const int SHAPE_TOPUP_MAX = 60;

// EffectAbilityIncrease counts against the server's max-ability-bonus (24) -
// the trap that made Legendary Feats abandon it for raw score writes. Stacked
// supernatural effects bypass that cap (mw_unlock_inc uses the same trick), so
// the top-up is emitted in chunks of this size.
const int SHAPE_TOPUP_CHUNK = 6;

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

// Returns ePoly with the stat top-ups linked into it, so that shifting adds
// the form's stock bonus to what oShifter already has instead of replacing it.
// Call AFTER ShapeMergeSnapshot and BEFORE the polymorph is applied, and apply
// the RETURNED effect. Linking is what makes this exploit-proof: unshifting,
// dispelling or the duration expiring takes the top-ups with the form, so
// nothing can survive into unshifted play.
effect ShapeMergeStatFloor(object oShifter, int nPoly, effect ePoly,
                           struct ShapeMergeGear gear);


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

// One polymorph.2da cell as an int. A blank ("****") column means the form
// keeps the character's own value, and Get2DAString gives "" for it.
int ShapeFormStat(int nPoly, string sColumn)
{
    string sVal = Get2DAString("polymorph", sColumn, nPoly);
    if (sVal == "") return 0;
    return StringToInt(sVal);
}

// Flat amount -> IP_CONST_DAMAGEBONUS_* constant.
//
// NOT the same table as DAMAGE_BONUS_* (the effect constants that
// IPGetDamageBonusConstantFromNumber returns): on the item-property side 6..10
// are 16..20, and 6..15 are DICE. Feeding a raw int to ItemPropertyDamageBonus
// turns a promised flat +7 into 1d6 - the same trap bonus_pool_inc documents
// for the effect side. Item properties top out at a flat +10.
int ShapeDamageIPConst(int nAmount)
{
    if (nAmount > 10) nAmount = 10;
    switch (nAmount)
    {
        case 1:  return IP_CONST_DAMAGEBONUS_1;
        case 2:  return IP_CONST_DAMAGEBONUS_2;
        case 3:  return IP_CONST_DAMAGEBONUS_3;
        case 4:  return IP_CONST_DAMAGEBONUS_4;
        case 5:  return IP_CONST_DAMAGEBONUS_5;
        case 6:  return IP_CONST_DAMAGEBONUS_6;
        case 7:  return IP_CONST_DAMAGEBONUS_7;
        case 8:  return IP_CONST_DAMAGEBONUS_8;
        case 9:  return IP_CONST_DAMAGEBONUS_9;
        case 10: return IP_CONST_DAMAGEBONUS_10;
    }
    return -1;
}

// The physical damage type an enhancement bonus would add to on this claw.
int ShapeClawDamageType(object oClaw)
{
    switch (GetBaseItemType(oClaw))
    {
        case BASE_ITEM_CPIERCWEAPON: return IP_CONST_DAMAGETYPE_PIERCING;
        case BASE_ITEM_CBLUDGWEAPON: return IP_CONST_DAMAGETYPE_BLUDGEONING;
    }
    // CSLASHWEAPON, CSLSHPRCWEAP and anything unexpected
    return IP_CONST_DAMAGETYPE_SLASHING;
}

// Copy a weapon's properties onto one of the form's natural attacks.
//
// Same job as IPWildShapeCopyItemProperties(oSrc, oClaw, TRUE), plus the fix
// for shifter-stats-defect: creature weapons ignore an enhancement bonus for
// attack and damage rolls (it only buys damage-reduction bypass), so a merged
// +9 weapon paid out nothing on a claw or bite. Re-express each enhancement
// bonus as the +n attack and +n physical damage it is supposed to be, and keep
// the original property for the DR bypass it still provides.
void ShapeCopyToCreatureWeapon(object oSrc, object oClaw)
{
    if (!GetIsObjectValid(oSrc) || !GetIsObjectValid(oClaw)) return;

    IPWildShapeCopyItemProperties(oSrc, oClaw, TRUE);

    if (!SHAPE_MERGE_ENH_AS_ATTACK) return;

    // The ranged-mismatch guard above skips everything for a bow; do not hand
    // the form a bow's enhancement bonus on its claws either.
    if (GetWeaponRanged(oSrc) != GetWeaponRanged(oClaw)) return;

    int nDamageType = ShapeClawDamageType(oClaw);
    itemproperty ip = GetFirstItemProperty(oSrc);
    while (GetIsItemPropertyValid(ip))
    {
        if (GetItemPropertyType(ip) == ITEM_PROPERTY_ENHANCEMENT_BONUS)
        {
            int nBonus = GetItemPropertyCostTableValue(ip);
            if (nBonus > 0)
            {
                AddItemProperty(DURATION_TYPE_PERMANENT,
                                ItemPropertyAttackBonus(nBonus), oClaw);

                int nDamage = ShapeDamageIPConst(nBonus);
                if (nDamage != -1)
                    AddItemProperty(DURATION_TYPE_PERMANENT,
                        ItemPropertyDamageBonus(nDamageType, nDamage), oClaw);
            }
        }
        ip = GetNextItemProperty(oSrc);
    }
}

// Link the top-up for one ability into eLink, per the rule in the file header:
// the character keeps their own base score and gains what the form is worth
// over a stock-rules character (SHAPE_BASE_ANCHOR).
effect ShapeAbilityTopUp(object oShifter, int nPoly, string sColumn,
                         int nAbility, effect eLink)
{
    int nForm = ShapeFormStat(nPoly, sColumn);
    if (nForm <= 0) return eLink;   // blank column: the form keeps your score

    int nBonus = nForm - SHAPE_BASE_ANCHOR;
    if (nBonus < 0) nBonus = 0;     // a weak form is not allowed to be a buff

    // The engine is about to set the base score to nForm, so the effect has to
    // carry the whole distance from there back up to the target.
    int nTopUp = GetAbilityScore(oShifter, nAbility, TRUE) + nBonus - nForm;
    if (nTopUp <= 0) return eLink;  // the form already beats the target
    if (nTopUp > SHAPE_TOPUP_MAX) nTopUp = SHAPE_TOPUP_MAX;

    while (nTopUp > 0)
    {
        int nChunk = nTopUp;
        if (nChunk > SHAPE_TOPUP_CHUNK) nChunk = SHAPE_TOPUP_CHUNK;
        eLink = EffectLinkEffects(eLink, EffectAbilityIncrease(nAbility, nChunk));
        nTopUp -= nChunk;
    }
    return eLink;
}

effect ShapeMergeStatFloor(object oShifter, int nPoly, effect ePoly,
                           struct ShapeMergeGear gear)
{
    if (!SHAPE_MERGE_STATS) return ePoly;

    ePoly = ShapeAbilityTopUp(oShifter, nPoly, "STR", ABILITY_STRENGTH,     ePoly);
    ePoly = ShapeAbilityTopUp(oShifter, nPoly, "CON", ABILITY_CONSTITUTION, ePoly);
    ePoly = ShapeAbilityTopUp(oShifter, nPoly, "DEX", ABILITY_DEXTERITY,    ePoly);

    // Armour and shield stop applying while shifted. Their PROPERTIES merge
    // onto the hide, but plate's own 8 AC cannot - hand it back, on top of the
    // form's natural bonus, so AC ends up "your AC plus what the form adds".
    // Natural is the same bonus type the form's own NATURALACBONUS uses and
    // only the highest of a type counts, so this supersedes it rather than
    // stacking with it. It also sidesteps MAX_AC_DODGE_MOD, which would eat
    // part of an AC_DODGE_BONUS.
    int nLost = 0;
    if (GetIsObjectValid(gear.oArmor))  nLost += GetItemACValue(gear.oArmor);
    if (GetIsObjectValid(gear.oShield)) nLost += GetItemACValue(gear.oShield);

    if (nLost > 0)
        ePoly = EffectLinkEffects(ePoly,
            EffectACIncrease(ShapeFormStat(nPoly, "NATURALACBONUS") + nLost,
                             AC_NATURAL_BONUS));

    return ePoly;
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
            // ShapeCopyToCreatureWeapon also re-expresses the enhancement
            // bonus, which creature weapons otherwise ignore.
            ShapeCopyToCreatureWeapon(oWeaponSrc,
                GetItemInSlot(INVENTORY_SLOT_CWEAPON_L, oShifter));
            ShapeCopyToCreatureWeapon(oWeaponSrc,
                GetItemInSlot(INVENTORY_SLOT_CWEAPON_R, oShifter));
            ShapeCopyToCreatureWeapon(oWeaponSrc,
                GetItemInSlot(INVENTORY_SLOT_CWEAPON_B, oShifter));

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
